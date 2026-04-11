// Klausemeister/Worktrees/CreateWorktreeSheetView.swift
import SwiftUI

/// Presentation component for the Create Worktree sheet. Takes plain values
/// and closures per CLAUDE.md — no store dependency. The sheet enforces a
/// single invariant at the UI level: the Create button is only enabled when
/// the entered name sanitizes to a non-empty, collision-free git branch name.
struct CreateWorktreeSheetView: View {
    let repositories: [Repository]
    let sheetState: CreateWorktreeSheetState
    var onRepoChanged: (String) -> Void
    var onNameChanged: (String) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    @Environment(\.themeColors) private var themeColors

    private var sanitized: SanitizedBranchName {
        WorktreeNameSanitizer.sanitize(sheetState.name)
    }

    private var collides: Bool {
        !sanitized.isEmpty && sheetState.existingBranches.contains(sanitized.value)
    }

    private var isSubmitDisabled: Bool {
        sheetState.repoId == nil || sanitized.isEmpty || collides
    }

    private var validationMessage: String? {
        let trimmed = sheetState.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if sanitized.isEmpty {
            return "Name has no characters that are valid in a git branch."
        }
        if collides {
            return "A branch named \"\(sanitized.value)\" already exists in this repository."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Worktree")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 14) {
                repositoryField
                nameField
            }

            HStack(spacing: 10) {
                Spacer()
                cancelButton
                createButton
            }
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 480)
        .glassPanel(tint: themeColors.accentColor)
        .padding(16)
    }

    // MARK: - Fields

    private var repositoryField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Repository")
            Picker(
                "Repository",
                selection: Binding(
                    get: { sheetState.repoId ?? "" },
                    set: { onRepoChanged($0) }
                )
            ) {
                ForEach(repositories) { repo in
                    Text(repo.name).tag(repo.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Name")
            TextField(
                "alpha",
                text: Binding(
                    get: { sheetState.name },
                    set: { onNameChanged($0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit { if !isSubmitDisabled { onSubmit() } }

            if sanitized.wasTransformed, !sanitized.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(sanitized.value)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            if let message = validationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.3)
    }

    // MARK: - Buttons

    private var cancelButton: some View {
        Button {
            onCancel()
        } label: {
            Text("Cancel")
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .keyboardShortcut(.cancelAction)
    }

    private var createButton: some View {
        Button {
            onSubmit()
        } label: {
            Text("Create")
                .font(.callout.weight(.semibold))
                .foregroundStyle(isSubmitDisabled ? .secondary : themeColors.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .disabled(isSubmitDisabled)
        .keyboardShortcut(.defaultAction)
    }
}
