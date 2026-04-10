// KlauseMCPShim/main.swift
//
// Tiny stdio↔Unix-socket bridge between the master Claude Code and
// Klausemeister.app. The plugin's `mcp.json` invokes this binary; the master
// Claude Code's MCP client speaks newline-delimited JSON over stdio (the
// stock MCP `StdioTransport`), and we forward bytes 1:1 to a Unix socket
// hosted by the running Klausemeister app.
//
// Klausemeister sets two env vars on the master process; we inherit them
// here and forward them as a single newline-terminated JSON "hello frame"
// before any MCP traffic, so the app can validate the master's identity
// and scope subsequent calls to the right worktree.
//
// IMPORTANT: This file is the entry point of a separate Xcode target
// (`KlauseMCPShim`, a Command Line Tool). The `HelloFrame` struct it shares
// with the app comes from `Klausemeister/MCP/HelloFrame.swift`, which is
// added to BOTH targets via Xcode's multi-target file membership.
import Foundation

// MARK: - Env validation

let env = ProcessInfo.processInfo.environment

guard env["KLAUSE_PRIMARY"] == "1" else {
    FileHandle.standardError.write(Data("klause-mcp-shim: KLAUSE_PRIMARY must be \"1\"\n".utf8))
    exit(2)
}

guard let worktreeId = env["KLAUSE_WORKTREE_ID"], !worktreeId.isEmpty else {
    FileHandle.standardError.write(Data("klause-mcp-shim: KLAUSE_WORKTREE_ID must be set\n".utf8))
    exit(2)
}

// MARK: - Socket path

let socketPath: String = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home
        .appendingPathComponent("Library")
        .appendingPathComponent("Application Support")
        .appendingPathComponent("Klausemeister")
        .appendingPathComponent("klause.sock")
        .path
}()

// MARK: - Connect

let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
guard socketFD >= 0 else {
    FileHandle.standardError.write(Data("klause-mcp-shim: socket() failed: \(String(cString: strerror(errno)))\n".utf8))
    exit(3)
}

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(socketPath.utf8)
guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
    FileHandle.standardError.write(Data("klause-mcp-shim: socket path too long\n".utf8))
    exit(3)
}

withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
    pathPtr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { cPathPtr in
        for (idx, byte) in pathBytes.enumerated() {
            cPathPtr[idx] = CChar(bitPattern: byte)
        }
        cPathPtr[pathBytes.count] = 0
    }
}

let addrSize = socklen_t(MemoryLayout<sockaddr_un>.size)
let connectResult = withUnsafePointer(to: &addr) { addrPtr in
    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
        connect(socketFD, sockaddrPtr, addrSize)
    }
}

guard connectResult == 0 else {
    let message = String(cString: strerror(errno))
    FileHandle.standardError.write(Data("klause-mcp-shim: connect to \(socketPath) failed: \(message)\n".utf8))
    close(socketFD)
    exit(3)
}

// MARK: - Hello frame

let hello = HelloFrame(klausePrimary: "1", klauseWorktreeId: worktreeId)
guard var helloData = try? JSONEncoder().encode(hello) else {
    FileHandle.standardError.write(Data("klause-mcp-shim: failed to encode hello frame\n".utf8))
    close(socketFD)
    exit(4)
}

helloData.append(0x0A) // newline terminator

/// Writes `data` fully to `fd`, retrying on partial writes. Returns true on
/// success, false if the write returns <= 0.
func writeAll(_ fileDescriptor: Int32, _ data: UnsafeRawBufferPointer) -> Bool {
    guard let base = data.baseAddress else { return true }
    var written = 0
    while written < data.count {
        let bytesWritten = write(fileDescriptor, base.advanced(by: written), data.count - written)
        if bytesWritten <= 0 { return false }
        written += bytesWritten
    }
    return true
}

helloData.withUnsafeBytes { bytes in
    _ = writeAll(socketFD, bytes)
}

// MARK: - Bidirectional pump

/// stdin → socket
let stdinReader = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .global(qos: .userInitiated))
stdinReader.setEventHandler {
    var buffer = [UInt8](repeating: 0, count: 65536)
    let bytesRead = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
        read(STDIN_FILENO, ptr.baseAddress, ptr.count)
    }
    if bytesRead <= 0 {
        stdinReader.cancel()
        shutdown(socketFD, SHUT_WR)
        return
    }
    let writeSucceeded = buffer.withUnsafeBytes { bytes -> Bool in
        let slice = UnsafeRawBufferPointer(rebasing: bytes.prefix(bytesRead))
        return writeAll(socketFD, slice)
    }
    if !writeSucceeded {
        stdinReader.cancel()
    }
}

stdinReader.resume()

/// socket → stdout
let socketReader = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: .global(qos: .userInitiated))
socketReader.setEventHandler {
    var buffer = [UInt8](repeating: 0, count: 65536)
    let bytesRead = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
        read(socketFD, ptr.baseAddress, ptr.count)
    }
    if bytesRead <= 0 {
        socketReader.cancel()
        exit(0)
    }
    let writeSucceeded = buffer.withUnsafeBytes { bytes -> Bool in
        let slice = UnsafeRawBufferPointer(rebasing: bytes.prefix(bytesRead))
        return writeAll(STDOUT_FILENO, slice)
    }
    if !writeSucceeded {
        socketReader.cancel()
        exit(0)
    }
}

socketReader.resume()

// Park forever; signals or socket close will exit via the read handlers above.
dispatchMain()
