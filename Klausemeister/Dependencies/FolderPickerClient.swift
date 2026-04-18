import AppKit
import Dependencies
import Foundation

/// Presents an `NSOpenPanel` configured for single-folder selection.
/// Wraps the panel so reducers can trigger a folder pick without
/// importing AppKit or breaking the view→reducer→dependency layering.
struct FolderPickerClient {
    /// Prompts the user to pick a folder. Returns the chosen URL, or
    /// `nil` if the user cancels. The implementation runs on the main
    /// actor because `NSOpenPanel` must be driven from the main thread.
    var pickFolder: @Sendable (_ message: String, _ prompt: String) async -> URL?
}

extension FolderPickerClient: DependencyKey {
    nonisolated static let liveValue = FolderPickerClient(
        pickFolder: { message, prompt in
            await MainActor.run {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.message = message
                panel.prompt = prompt
                return panel.runModal() == .OK ? panel.url : nil
            }
        }
    )

    nonisolated static let testValue = FolderPickerClient(
        pickFolder: unimplemented("FolderPickerClient.pickFolder", placeholder: nil)
    )
}

extension DependencyValues {
    var folderPickerClient: FolderPickerClient {
        get { self[FolderPickerClient.self] }
        set { self[FolderPickerClient.self] = newValue }
    }
}
