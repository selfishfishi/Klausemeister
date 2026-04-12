// klause-mcp-shim/ShimStateFilePersistence.swift
// State file persistence so the respawn wrapper and Klausemeister can discover
// active shims. Written on state transitions, deleted on clean exit.
import Foundation

extension ShimBridge {
    /// Writes the state file for discovery. Must be called on `stateQueue`.
    func writeStateFile(status: String) {
        let stateDir = (stateFilePath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(
                atPath: stateDir,
                withIntermediateDirectories: true
            )
        } catch {
            log("failed to create state dir \(stateDir): \(error.localizedDescription)")
            return
        }
        let file = ShimStateFile(
            worktreeId: worktreeId,
            pid: ProcessInfo.processInfo.processIdentifier,
            status: status,
            socketPath: socketPath,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        guard let data = try? JSONEncoder().encode(file) else {
            log("failed to encode state file JSON")
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: stateFilePath), options: .atomicWrite)
        } catch {
            log("failed to write state file: \(error.localizedDescription)")
        }
    }

    /// Removes the state file on clean exit (stdin EOF).
    func deleteStateFile() {
        do {
            try FileManager.default.removeItem(atPath: stateFilePath)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError
        {
            // Already gone — fine.
        } catch {
            log("failed to delete state file: \(error.localizedDescription)")
        }
    }
}
