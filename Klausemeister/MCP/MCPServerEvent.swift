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

    /// A tool reported ambient narration ("what the meister is doing right now").
    /// Unlike `progressReported` this has no `itemId` — activity is session-scoped,
    /// not ticket-scoped, so the meister can narrate while idle or between tickets.
    /// The UI shows it as a ticker-style scrolling line that decays after ~30s
    /// of silence, falling back to the static status label.
    case activityReported(worktreeId: String, text: String)

    /// The meister Claude Code for the given worktree completed its handshake
    /// (shim sent a valid HelloFrame). `WorktreeFeature` uses this to flip
    /// the worktree's `meisterStatus` to `.running`.
    case meisterHelloReceived(worktreeId: String)

    /// The meister's MCP connection terminated — either because `claude`
    /// exited, the shim disconnected, or the transport errored. Flips the
    /// worktree to `.disconnected`. KLA-74 spec forbids auto-respawn.
    case meisterConnectionClosed(worktreeId: String)

    /// An MCP tool moved a queue item from inbox to processing (e.g.
    /// `getNextItem` or `transition("pull")`). `WorktreeFeature` uses
    /// this to sync its in-memory state with the DB mutation.
    case itemMovedToProcessing(worktreeId: String, issueLinearId: String)

    /// An MCP tool moved a queue item from processing to outbox (e.g.
    /// `completeItem` or `transition("push")`). `WorktreeFeature` uses
    /// this to sync its in-memory state with the DB mutation.
    case itemMovedToOutbox(worktreeId: String, issueLinearId: String)

    /// An MCP tool added a new item to a worktree's inbox (e.g.
    /// `enqueueItem`). `WorktreeFeature` uses this to sync its
    /// in-memory state with the DB mutation.
    case itemAddedToInbox(worktreeId: String, issueLinearId: String)
}
