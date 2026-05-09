// Klausemeister/MCP/SocketTransport.swift
import Foundation
import Logging
import MCP
import Synchronization

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
        try await Self.awaitReadable(socketFD: socketFD, bufferSize: 65536)
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
            let chunk = try await awaitReadable(socketFD: socketFD, bufferSize: 4096)
            buffer.append(chunk)
            if let nlIndex = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: 0 ..< nlIndex)
                let remainder = buffer.subdata(in: (nlIndex + 1) ..< buffer.endIndex)
                return (line, remainder)
            }
        }
    }

    /// Waits for `socketFD` to become readable, performs a single `read()`,
    /// and returns the bytes read.
    ///
    /// The read is driven by a `DispatchSource`. If the surrounding Swift
    /// `Task` is cancelled mid-read the source is cancelled so the file
    /// descriptor and the source object are not leaked — which would
    /// otherwise happen on every MCP disconnect.
    ///
    /// A `Mutex<Bool>` guards against the three possible resume races:
    /// 1. the event handler firing and resuming,
    /// 2. the cancel handler resuming with `CancellationError()`, and
    /// 3. `onCancel` calling `source.cancel()` which itself invokes the
    ///    cancel handler.
    /// Whichever path wins resumes the continuation exactly once.
    static func awaitReadable(socketFD: Int32, bufferSize: Int) async throws -> Data {
        let resumed = Mutex<Bool>(false)
        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: .global(qos: .userInitiated))

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Swift.Error>) in
                source.setEventHandler {
                    var buf = [UInt8](repeating: 0, count: bufferSize)
                    let bytesRead = buf.withUnsafeMutableBufferPointer { ptr in
                        Darwin.read(Int32(source.handle), ptr.baseAddress, ptr.count)
                    }
                    let shouldResume = resumed.withLock { flag -> Bool in
                        guard !flag else { return false }
                        flag = true
                        return true
                    }
                    guard shouldResume else {
                        source.cancel()
                        return
                    }
                    source.cancel()
                    if bytesRead > 0 {
                        cont.resume(returning: Data(buf.prefix(bytesRead)))
                    } else {
                        cont.resume(throwing: SocketTransportError.closed)
                    }
                }
                source.setCancelHandler {
                    let shouldResume = resumed.withLock { flag -> Bool in
                        guard !flag else { return false }
                        flag = true
                        return true
                    }
                    guard shouldResume else { return }
                    cont.resume(throwing: CancellationError())
                }
                source.resume()
            }
        } onCancel: {
            // Cancelling the source drains any pending event handler and
            // fires the cancel handler on the dispatch queue, which resumes
            // the continuation if it has not been resumed yet.
            source.cancel()
        }
    }
}
