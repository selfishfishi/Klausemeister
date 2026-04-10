// Klausemeister/Dependencies/MCPServerClient.swift
import Dependencies
import Foundation

/// TCA dependency client wrapping the in-process MCP server.
///
/// `start()` boots the Unix-socket listener (defined in
/// `Klausemeister/MCP/MCPSocketListener.swift`) and returns only when it
/// terminates — typically when the app quits and the effect is cancelled.
///
/// `events()` returns the bridge `AsyncStream` over which the listener pushes
/// errors and progress reports back into TCA. `AppFeature` consumes it via a
/// long-lived `.run` effect, mirroring how `OAuthClient` bridges callback URLs.
struct MCPServerClient {
    var start: @Sendable () async -> Void
    var events: @Sendable () -> AsyncStream<MCPServerEvent>
}

extension MCPServerClient: DependencyKey {
    nonisolated static let liveValue: MCPServerClient = {
        let (stream, continuation) = AsyncStream.makeStream(of: MCPServerEvent.self)

        return MCPServerClient(
            start: {
                await MCPSocketListener.run(eventContinuation: continuation)
            },
            events: { stream }
        )
    }()

    nonisolated static let testValue = MCPServerClient(
        start: unimplemented("MCPServerClient.start"),
        events: unimplemented("MCPServerClient.events", placeholder: AsyncStream { _ in })
    )
}

extension DependencyValues {
    var mcpServerClient: MCPServerClient {
        get { self[MCPServerClient.self] }
        set { self[MCPServerClient.self] = newValue }
    }
}
