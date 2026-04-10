// Klausemeister/MCP/MCPServerEvent.swift
import Foundation

/// Events the MCP server pushes up into TCA via `MCPServerClient.events()`.
///
/// The MCP server runs in a long-lived `nonisolated` context outside the TCA store.
/// It bridges back into TCA by yielding values on an `AsyncStream<MCPServerEvent>`,
/// which `AppFeature` consumes via a long-lived `.run` effect (mirroring how
/// `OAuthClient` bridges its callback URL into the store).
enum MCPServerEvent: Equatable {
    /// A tool failed. The message is propagated to `StatusBarFeature` for display.
    case errorOccurred(message: String)

    /// A tool reported live progress. The text is opaque — `StatusBarFeature`
    /// (or, eventually, the per-session sidebar UI in KLA-80) decides how to render it.
    case progressReported(worktreeId: String, itemId: String, statusText: String)
}
