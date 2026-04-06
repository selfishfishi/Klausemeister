// Klausemeister/Worktrees/CreateWorktreeSheetView.swift
import SwiftUI

/// Presentation component for the Create Worktree sheet. Takes plain values
/// and closures per CLAUDE.md — no store dependency.
struct CreateWorktreeSheetView: View {
    let repositories: [Repository]
    let sheetState: CreateWorktreeSheetState
    var onRepoChanged: (String) -> Void
    var onNameChanged: (String) -> Void
    var onBranchChoiceChanged: (CreateWorktreeSheetState.BranchChoice) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    private enum BranchMode: String, CaseIterable, Identifiable {
        case newFromDefault
        case existing

        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .newFromDefault: "New branch"
            case .existing: "Existing branch"
            }
        }
    }

    private var branchMode: BranchMode {
        switch sheetState.branchChoice {
        case .newFromDefault: .newFromDefault
        case .existing: .existing
        }
    }

    private var isSubmitDisabled: Bool {
        if sheetState.repoId == nil { return true }
        let trimmed = sheetState.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if case .existing("") = sheetState.branchChoice { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Worktree")
                .font(.title2.weight(.semibold))

            Form {
                Picker("Repository", selection: Binding(
                    get: { sheetState.repoId ?? "" },
                    set: { onRepoChanged($0) }
                )) {
                    ForEach(repositories) { repo in
                        Text(repo.name).tag(repo.id)
                    }
                }

                TextField("Name", text: Binding(
                    get: { sheetState.name },
                    set: { onNameChanged($0) }
                ))

                Picker("Branch", selection: Binding(
                    get: { branchMode },
                    set: { newMode in
                        switch newMode {
                        case .newFromDefault:
                            onBranchChoiceChanged(.newFromDefault)
                        case .existing:
                            let first = sheetState.branches.first ?? ""
                            onBranchChoiceChanged(.existing(first))
                        }
                    }
                )) {
                    ForEach(BranchMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if case let .existing(selected) = sheetState.branchChoice {
                    if sheetState.isLoadingBranches {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Loading branches…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if sheetState.branches.isEmpty {
                        Text("No branches found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Existing", selection: Binding(
                            get: { selected },
                            set: { onBranchChoiceChanged(.existing($0)) }
                        )) {
                            ForEach(sheetState.branches, id: \.self) { branch in
                                Text(branch).tag(branch)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: onSubmit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSubmitDisabled)
            }
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 460)
    }
}
