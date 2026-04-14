import ComposableArchitecture
import SwiftUI

struct MeisterView: View {
    @Bindable var store: StoreOf<MeisterFeature>
    let worktrees: [Worktree]
    let repositories: [Repository]
    var assignedWorktreeNames: [String: String] = [:]
    var teams: [LinearTeam] = []
    var onManageTeams: (() -> Void)?

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(spacing: 0) {
            // Header with filter + sync
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                    TextField("Search issues…", text: $store.searchQuery)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: 200)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 7))

                Spacer()
                if teams.count > 1 {
                    TeamFilterMenu(
                        teams: teams,
                        hiddenTeamIds: store.hiddenTeamIds,
                        themeColors: themeColors,
                        onToggle: { teamId in
                            store.send(
                                .teamFilterToggled(teamId: teamId),
                                animation: .smooth(duration: 0.2)
                            )
                        }
                    )
                }
                if store.allProjectNames.count > 1 {
                    ProjectFilterMenu(
                        projectNames: store.allProjectNames,
                        hiddenProjectNames: store.hiddenProjectNames,
                        onToggle: { projectName in
                            store.send(
                                .projectFilterToggled(projectName: projectName),
                                animation: .smooth(duration: 0.2)
                            )
                        }
                    )
                }
                Menu {
                    Button("Configure stage mappings") {
                        store.send(.stateMappingButtonTapped)
                    }
                } label: {
                    Image(systemName: "arrow.left.arrow.right.circle")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.secondary)
                } primaryAction: {
                    store.send(.stateMappingButtonTapped)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .tint(Color(nsColor: .secondaryLabelColor))
                .help("Configure stage mappings")
                StageFilterMenu(
                    hiddenStages: store.hiddenStages,
                    onToggle: { stage in
                        store.send(
                            .stageVisibilityToggled(stage),
                            animation: .smooth(duration: 0.2)
                        )
                    }
                )
                SyncIndicatorMenu(
                    syncStatus: store.syncStatus,
                    onRefresh: { store.send(.refreshTapped) },
                    onReloadMetadata: { store.send(.refreshLinearMetadataTapped) }
                )
                if let onManageTeams {
                    Menu {
                        Button("Manage teams") { onManageTeams() }
                    } label: {
                        Image(systemName: "gearshape.circle")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(.secondary)
                    } primaryAction: {
                        onManageTeams()
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .tint(Color(nsColor: .secondaryLabelColor))
                    .help("Manage teams")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            // Kanban board
            GeometryReader { proxy in
                let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(store.visibleColumns) { column in
                            KanbanColumnView(
                                column: column,
                                worktrees: worktrees,
                                repositories: repositories,
                                assignedWorktreeNames: assignedWorktreeNames,
                                teamsByID: teams.count > 1 ? teamsByID : [:],
                                onMoveToStatus: { issueId, target in
                                    store.send(.moveToStatusTapped(issueId: issueId, target: target))
                                },
                                onAssignToWorktree: { issue, worktreeId in
                                    store.send(.assignIssueToWorktree(issue: issue, worktreeId: worktreeId))
                                },
                                onRemove: { issueId in
                                    store.send(.removeIssueTapped(issueId: issueId))
                                },
                                onDrop: { issueId in
                                    store.send(.issueDropped(issueId: issueId, onColumn: column.id))
                                },
                                onAdvance: { worktreeId in
                                    store.send(.advanceWorkflowTapped(worktreeId: worktreeId))
                                }
                            )
                            .transition(
                                .scale(scale: 0.85)
                                    .combined(with: .opacity)
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 16)
                    .frame(minWidth: proxy.size.width, alignment: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { store.send(.onAppear) }
        .sheet(item: $store.scope(state: \.stateMappingEditor, action: \.stateMappingEditor)) { editorStore in
            StateMappingView(store: editorStore)
        }
    }
}

// MARK: - Sync Indicator Button

private struct SyncIndicatorMenu: View {
    let syncStatus: MeisterFeature.SyncStatus
    let onRefresh: () -> Void
    let onReloadMetadata: () -> Void

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        Menu {
            Button {
                onRefresh()
            } label: {
                Label("Refresh issues", systemImage: "arrow.clockwise")
            }
            Button {
                onReloadMetadata()
            } label: {
                Label("Reload Linear metadata", systemImage: "arrow.triangle.2.circlepath")
            }
        } label: {
            image
                .font(.system(size: 44, weight: .semibold))
        } primaryAction: {
            onRefresh()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(syncStatus == .syncing)
        .help(helpText)
    }

    @ViewBuilder
    private var image: some View {
        switch syncStatus {
        case .idle:
            Image(systemName: "arrow.clockwise")
                .foregroundStyle(.secondary)
        case .syncing:
            ProgressView()
                .controlSize(.small)
                .tint(themeColors.accentColor)
        case .succeeded:
            Image(systemName: "checkmark")
                .foregroundStyle(themeColors.accentColor)
                .transition(.opacity)
        }
    }

    private var helpText: String {
        switch syncStatus {
        case .idle: "Sync issues"
        case .syncing: "Syncing..."
        case .succeeded: "Sync complete"
        }
    }
}

// MARK: - Stage Filter Menu (Liquid Glass)

private struct StageFilterMenu: View {
    let hiddenStages: Set<MeisterState>
    let onToggle: (MeisterState) -> Void

    var body: some View {
        Menu {
            ForEach(MeisterState.allCases) { stage in
                Button {
                    onToggle(stage)
                } label: {
                    if hiddenStages.contains(stage) {
                        Text(stage.displayName)
                    } else {
                        Label(stage.displayName, systemImage: "checkmark")
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .tint(Color(nsColor: .secondaryLabelColor))
        .help("Filter visible columns")
    }
}

// MARK: - Team Filter Menu

private struct TeamFilterMenu: View {
    let teams: [LinearTeam]
    let hiddenTeamIds: Set<String>
    let themeColors: ThemeColors
    let onToggle: (String) -> Void

    var body: some View {
        Menu {
            ForEach(teams) { team in
                Button {
                    onToggle(team.id)
                } label: {
                    let isVisible = !hiddenTeamIds.contains(team.id)
                    if isVisible {
                        Label(team.key, systemImage: "checkmark")
                    } else {
                        Text(team.key)
                    }
                }
            }
        } label: {
            Image(systemName: "person.2.circle")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .tint(Color(nsColor: .secondaryLabelColor))
        .help("Filter visible teams")
    }
}

// MARK: - Project Filter Menu

private struct ProjectFilterMenu: View {
    let projectNames: [String]
    let hiddenProjectNames: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        Menu {
            ForEach(projectNames, id: \.self) { name in
                Button {
                    onToggle(name)
                } label: {
                    let displayName = name == LinearIssue.noProjectName ? "(No project)" : name
                    let isVisible = !hiddenProjectNames.contains(name)
                    if isVisible {
                        Label(displayName, systemImage: "checkmark")
                    } else {
                        Text(displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "folder.circle")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .tint(Color(nsColor: .secondaryLabelColor))
        .help("Filter visible projects")
    }
}
