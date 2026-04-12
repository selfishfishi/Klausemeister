// Klausemeister/Worktrees/CreateWorktreeSheetView.swift
import SwiftUI

/// Presentation component for the Create Worktree sheet. Takes plain values
/// and closures per CLAUDE.md — no store dependency. The sheet enforces a
/// single invariant at the UI level: the Create button is only enabled when
/// the entered name sanitizes to a non-empty, collision-free git branch name.
struct CreateWorktreeSheetView: View {
    let repositories: [Repository]
    let sheetState: CreateWorktreeSheetState
    var onNameChanged: (String) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    @Environment(\.themeColors) private var themeColors

    private var sanitized: SanitizedBranchName {
        WorktreeNameSanitizer.sanitize(sheetState.name)
    }

    private var willReuseExistingBranch: Bool {
        !sanitized.isEmpty && sheetState.existingBranches.contains(sanitized.value)
    }

    private var isSubmitDisabled: Bool {
        sheetState.repoId == nil || sanitized.isEmpty
    }

    private var errorMessage: String? {
        let trimmed = sheetState.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if sanitized.isEmpty {
            return "Name has no characters that are valid in a git branch."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("New Worktree")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 20) {
                repositoryField
                nameField
            }

            HStack(spacing: 12) {
                Spacer()
                cancelButton
                createButton
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(minWidth: 460, idealWidth: 500)
        .tint(themeColors.accentColor)
        .glassPanel(tint: themeColors.accentColor)
        .presentationBackground(.clear)
    }

    // MARK: - Fields

    private static let labelColumnWidth: CGFloat = 96

    private var repositoryField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            fieldLabel("Repository")
                .frame(width: Self.labelColumnWidth, alignment: .leading)
            if let repo = repositories.first(where: { $0.id == sheetState.repoId }) {
                Text(repo.name)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
    }

    private var nameField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            fieldLabel("Name")
                .frame(width: Self.labelColumnWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                TextField(
                    "alpha",
                    text: Binding(
                        get: { sheetState.name },
                        set: { onNameChanged($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { if !isSubmitDisabled { onSubmit() } }

                VStack(alignment: .leading, spacing: 4) {
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

                    if willReuseExistingBranch {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("Will reuse existing branch \"\(sanitized.value)\".")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let message = errorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.top, 2)
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
