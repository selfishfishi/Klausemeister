// Klausemeister/MCP/SocketTransport.swift
import Foundation
import Logging
import MCP

/// MCP `Transport` conformance for a single Unix-domain-socket connection,
/// backed by a raw POSIX file descriptor.
///
/// The wire format is newline-delimited JSON-RPC, matching how
/// `StdioTransport` frames messages. This works with our shim binary, which
/// reads stdin/stdout from the meister Claude Code (also newline-framed) and
/// forwards bytes 1:1 to the socket.
///
/// One `SocketTransport` is created per accepted connection. The
/// `MCPSocketListener` parses and validates the leading "hello" frame from
/// the connection BEFORE constructing the transport, so by the time
/// `connect()` is called the next bytes are the meister's first MCP request.
actor SocketTransport: Transport {
    nonisolated let logger: Logger

    private let socketFD: Int32
    private var receiveTask: Task<Void, Never>?
    private let messageStream: AsyncThrowingStream<Data, Swift.Error>
    private let messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation
    private var buffer = Data()
    private var isClosed = false

    init(socketFD: Int32, logger: Logger, initialData: Data = Data()) {
        self.socketFD = socketFD
        self.logger = logger
        buffer = initialData
        var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        messageStream = AsyncThrowingStream<Data, Swift.Error> { continuation = $0 }
        messageContinuation = continuation
    }

    deinit {
        close(socketFD)
    }

    // MARK: - Transport

    func connect() async throws {
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func disconnect() async {
        guard !isClosed else { return }
        isClosed = true
        receiveTask?.cancel()
        messageContinuation.finish()
        shutdown(socketFD, SHUT_RDWR)
    }

    func send(_ message: Data) async throws {
        guard !isClosed else { throw SocketTransportError.closed }
        var framed = message
        framed.append(0x0A)
        try writeAll(framed)
    }

    nonisolated func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        messageStream
    }

    // MARK: - Internals

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var written = 0
            while written < bytes.count {
                let result = Darwin.write(socketFD, base.advanced(by: written), bytes.count - written)
                if result <= 0 {
                    throw SocketTransportError.closed
                }
                written += result
            }
        }
    }

    private func receiveLoop() async {
        drainBuffer()

        while !Task.isCancelled, !isClosed {
            do {
                let chunk = try await receiveChunk()
                buffer.append(chunk)
                drainBuffer()
            } catch {
                if !isClosed {
                    messageContinuation.finish(throwing: error)
                }
                return
            }
        }
        messageContinuation.finish()
    }

    private func drainBuffer() {
        while let nlIndex = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: 0 ..< nlIndex)
            buffer.removeSubrange(buffer.startIndex ... nlIndex)
            if !line.isEmpty {
                messageContinuation.yield(line)
            }
        }
    }

    private func receiveChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { [socketFD] in
                var buf = [UInt8](repeating: 0, count: 65536)
                let bytesRead = buf.withUnsafeMutableBufferPointer { ptr in
                    Darwin.read(socketFD, ptr.baseAddress, ptr.count)
                }
                if bytesRead > 0 {
                    cont.resume(returning: Data(buf.prefix(bytesRead)))
                } else {
                    cont.resume(throwing: SocketTransportError.closed)
                }
            }
        }
    }
}

enum SocketTransportError: Error, Equatable {
    case closed
}

// MARK: - Hello frame helpers

extension SocketTransport {
    /// Reads bytes from a file descriptor until a newline is found, returning
    /// everything before the newline. Used by `MCPSocketListener` to consume
    /// the hello frame BEFORE handing the connection to a `SocketTransport`.
    static func readHelloLine(from socketFD: Int32) async throws -> (line: Data, remainder: Data) {
        var buffer = Data()
        while true {
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    var buf = [UInt8](repeating: 0, count: 4096)
                    let bytesRead = buf.withUnsafeMutableBufferPointer { ptr in
                        Darwin.read(socketFD, ptr.baseAddress, ptr.count)
                    }
                    if bytesRead > 0 {
                        cont.resume(returning: Data(buf.prefix(bytesRead)))
                    } else {
                        cont.resume(throwing: SocketTransportError.closed)
                    }
                }
            }
            buffer.append(chunk)
            if let nlIndex = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: 0 ..< nlIndex)
                let remainder = buffer.subdata(in: (nlIndex + 1) ..< buffer.endIndex)
                return (line, remainder)
            }
        }
    }
}
