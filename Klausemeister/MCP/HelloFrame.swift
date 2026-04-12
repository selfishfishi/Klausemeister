// Klausemeister/MCP/HelloFrame.swift
//
// Wire format for the handshake the shim sends to the app immediately
// after connecting to the Unix socket, before any MCP traffic.
//
// IMPORTANT: This file is a member of TWO targets — `Klausemeister` and
// `KlauseMCPShim` — via Xcode's multi-target file membership. Do not
// duplicate the struct in the shim sources; both targets must agree on
// the wire format and a single source of truth prevents drift.
import Foundation

nonisolated struct HelloFrame: Codable, Equatable {
    /// Must equal `"1"`. Set by Klausemeister when spawning the meister Claude
    /// Code; inherited by the shim subprocess; forwarded here.
    let klauseMeister: String

    /// Worktree UUID this connection is allowed to act on.
    let klauseWorktreeId: String

    /// Validates the frame meets the minimum requirements to identify a meister.
    nonisolated var isValidMeister: Bool {
        klauseMeister == "1" && !klauseWorktreeId.isEmpty
    }
}
