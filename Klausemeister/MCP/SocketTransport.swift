// Klausemeister/MCP/SocketTransport.swift
import Foundation
import Logging
import MCP
import Network

/// MCP `Transport` conformance for a single Unix-domain-socket connection.
///
/// The wire format is newline-delimited JSON-RPC, matching how
/// `StdioTransport` frames messages. This works with our shim binary, which
/// reads stdin/stdout from the meister Claude Code (also newline-framed) and
/// forwards bytes 1:1 to the socket.
///
/// One `SocketTransport` is created per accepted connection. The
/// `MCPSocketListener` parses and validates the leading "hello" frame from
/// the connection BEFORE constructing the transport, so by the time
/// `connect()` is called the next bytes from the underlying NWConnection are
/// the meister's first MCP request.
actor SocketTransport: Transport {
    nonisolated let logger: Logger

    private let connection: NWConnection
    private var receiveTask: Task<Void, Never>?
    private let messageStream: AsyncThrowingStream<Data, Swift.Error>
    private let messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation
    private var buffer = Data()
    private var isClosed = false

    init(connection: NWConnection, logger: Logger) {
        self.connection = connection
        self.logger = logger
        var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        messageStream = AsyncThrowingStream<Data, Swift.Error> { continuation = $0 }
        messageContinuation = continuation
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
        connection.cancel()
    }

    func send(_ message: Data) async throws {
        guard !isClosed else { throw SocketTransportError.closed }
        var framed = message
        framed.append(0x0A) // newline
        try await sendRaw(framed)
    }

    nonisolated func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        messageStream
    }

    // MARK: - Internals

    private func sendRaw(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Swift.Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled, !isClosed {
            do {
                let chunk = try await receiveChunk()
                buffer.append(chunk)
                while let nlIndex = buffer.firstIndex(of: 0x0A) {
                    let line = buffer.subdata(in: 0 ..< nlIndex)
                    buffer.removeSubrange(buffer.startIndex ... nlIndex)
                    if !line.isEmpty {
                        messageContinuation.yield(line)
                    }
                }
            } catch {
                if !isClosed {
                    messageContinuation.finish(throwing: error)
                }
                return
            }
        }
        messageContinuation.finish()
    }

    private func receiveChunk() async throws -> Data {
        // Loop until we get actual bytes or a terminal condition.
        // NWConnection.receive can fire with empty data on spurious wakes;
        // returning Data() would cause a busy-loop in receiveLoop.
        while true {
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                    if let error {
                        cont.resume(throwing: error)
                        return
                    }
                    if let data, !data.isEmpty {
                        cont.resume(returning: data)
                        return
                    }
                    if isComplete {
                        cont.resume(throwing: SocketTransportError.closed)
                        return
                    }
                    // Spurious wake — resume with empty to retry
                    cont.resume(returning: Data())
                }
            }
            if !chunk.isEmpty { return chunk }
        }
    }
}

enum SocketTransportError: Error, Equatable {
    case closed
    case malformedHelloFrame
    case unauthorized
}

// MARK: - Hello frame helpers

extension SocketTransport {
    /// Reads bytes from an `NWConnection` until a newline is found, returning
    /// everything before the newline. Used by `MCPSocketListener` to consume the
    /// hello frame BEFORE handing the connection to a `SocketTransport`.
    ///
    /// Anything read past the newline is returned in `remainder` so the caller
    /// can prepend it to the transport's buffer (in practice the shim sends the
    /// hello frame alone before MCP traffic, so `remainder` is usually empty).
    static func readHelloLine(from connection: NWConnection) async throws -> (line: Data, remainder: Data) {
        var buffer = Data()
        while true {
            let chunk = try await readNonEmptyChunk(from: connection)
            buffer.append(chunk)
            if let nlIndex = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: 0 ..< nlIndex)
                let remainder = buffer.subdata(in: (nlIndex + 1) ..< buffer.endIndex)
                return (line, remainder)
            }
        }
    }

    /// Shared helper that reads from a connection, retrying on spurious empty wakes.
    private static func readNonEmptyChunk(from connection: NWConnection) async throws -> Data {
        while true {
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                    if let error {
                        cont.resume(throwing: error)
                        return
                    }
                    if let data, !data.isEmpty {
                        cont.resume(returning: data)
                        return
                    }
                    if isComplete {
                        cont.resume(throwing: SocketTransportError.closed)
                        return
                    }
                    cont.resume(returning: Data())
                }
            }
            if !chunk.isEmpty { return chunk }
        }
    }
}
