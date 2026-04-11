import SwiftUI

struct AddWorktreeInlineButton: View {
    let onSubmit: (_ name: String) -> Void

    @State private var isEditing = false
    @State private var name = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        if isEditing {
            HStack(spacing: 4) {
                TextField("Worktree name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(maxWidth: 140)
                    .focused($fieldFocused)
                    .onSubmit { submit() }
                Button {
                    cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .onAppear { fieldFocused = true }
        } else {
            Button {
                isEditing = true
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("New worktree")
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancel()
            return
        }
        onSubmit(trimmed)
        cancel()
    }

    private func cancel() {
        name = ""
        isEditing = false
    }
}
