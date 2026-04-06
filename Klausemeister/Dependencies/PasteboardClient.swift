import AppKit
import Dependencies
import Foundation

struct PasteboardClient {
    var setString: @Sendable (String) async -> Void
}

extension PasteboardClient: DependencyKey {
    nonisolated static let liveValue = PasteboardClient(
        setString: { string in
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(string, forType: .string)
            }
        }
    )

    nonisolated static let testValue = PasteboardClient(
        setString: unimplemented("PasteboardClient.setString")
    )
}

extension DependencyValues {
    var pasteboard: PasteboardClient {
        get { self[PasteboardClient.self] }
        set { self[PasteboardClient.self] = newValue }
    }
}
