// klause-mcp-shim/StubMCPServer.swift
//
// Minimal MCP-protocol-compliant server used when the shim is launched
// outside a meister context (no `KLAUSE_MEISTER=1` env var).
//
// Codex registers `klausemeister` as a global MCP server in
// `~/.codex/config.toml`, so it tries to spawn the shim on every Codex
// session — including plain `codex` invocations the user runs in any
// terminal. Pre-fix, the shim's worker exited 2 in that case, which Codex
// surfaces as: "MCP client for `klausemeister` failed to start: MCP startup
// failed: handshaking with MCP server failed: connection closed: initialize
// response". Claude tolerates a fast-exiting MCP server silently; Codex
// does not.
//
// The stub responds to `initialize`, `tools/list`, `prompts/list`,
// `resources/list`, `resources/templates/list`, and `ping` with empty
// data, and returns method-not-found for anything else. Stays alive on
// stdin until EOF, then exits cleanly. From Codex's perspective this is
// a healthy MCP server that simply has nothing to offer — no error, no
// noise, no spurious tools available outside meister sessions.
import Foundation

enum StubMCPServer {
    static func run() -> Never {
        shimDebugLog("stub: starting (KLAUSE_MEISTER not set — non-meister mode)")
        let stdin = FileHandle.standardInput
        let stdout = FileHandle.standardOutput
        var buffer = Data()

        while true {
            // `availableData` blocks until bytes arrive or stdin closes;
            // returns empty Data on EOF, which is the cue to exit cleanly.
            let chunk = stdin.availableData
            if chunk.isEmpty {
                shimDebugLog("stub: stdin EOF, exiting 0")
                exit(0)
            }
            buffer.append(chunk)
            // MCP stdio framing is line-delimited JSON — drain every
            // complete line currently in the buffer.
            while let newlineIdx = buffer.firstIndex(of: 0x0A) {
                let lineRange = buffer.startIndex ..< newlineIdx
                let lineData = Data(buffer[lineRange])
                buffer.removeSubrange(buffer.startIndex ... newlineIdx)
                guard !lineData.isEmpty else { continue }
                handleLine(lineData, stdout: stdout)
            }
            // Cap the buffer so a peer that never sends a newline cannot
            // make us grow unbounded.
            if buffer.count > 1_048_576 {
                shimDebugLog("stub: stdin line buffer exceeded 1 MiB, dropping")
                buffer.removeAll(keepingCapacity: true)
            }
        }
    }

    private static func handleLine(_ data: Data, stdout: FileHandle) {
        guard let parsed = try? JSONSerialization.jsonObject(with: data),
              let json = parsed as? [String: Any]
        else {
            shimDebugLog("stub: unparseable JSON-RPC line, ignored")
            return
        }
        let method = json["method"] as? String ?? ""
        let id = json["id"]
        // Notifications carry no `id` and expect no response. The most
        // common one is `notifications/initialized` post-handshake.
        guard id != nil else {
            shimDebugLog("stub: notification \(method) (no response)")
            return
        }

        var response: [String: Any] = ["jsonrpc": "2.0", "id": id!]
        switch method {
        case "initialize":
            // Advertise no capabilities — clients should therefore not
            // call tools/prompts/resources methods at all. We still
            // implement those handlers below as defensive empty
            // responses for clients that probe regardless.
            response["result"] = [
                "protocolVersion": "2024-11-05",
                "capabilities": [String: Any](),
                "serverInfo": [
                    "name": "klausemeister-stub",
                    "version": "1.0.0"
                ]
            ]
        case "tools/list":
            response["result"] = ["tools": [Any]()]
        case "prompts/list":
            response["result"] = ["prompts": [Any]()]
        case "resources/list":
            response["result"] = ["resources": [Any]()]
        case "resources/templates/list":
            response["result"] = ["resourceTemplates": [Any]()]
        case "ping":
            response["result"] = [String: Any]()
        default:
            response["error"] = [
                "code": -32601,
                "message": "Method not found: \(method)"
            ]
        }

        guard let outData = try? JSONSerialization.data(
            withJSONObject: response,
            options: [.withoutEscapingSlashes]
        ) else {
            shimDebugLog("stub: failed to serialize response for \(method)")
            return
        }
        var framed = outData
        framed.append(0x0A)
        // FileHandle.write goes straight to write(2) on the underlying
        // fd, bypassing C stdio buffering — Codex sees the response as
        // soon as the syscall returns.
        stdout.write(framed)
    }
}
