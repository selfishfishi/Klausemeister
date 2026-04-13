import ComposableArchitecture
import SwiftUI

struct TeamSettingsView: View {
    @Bindable var store: StoreOf<TeamSettingsFeature>

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            contentSection
            footerSection
        }
        .frame(width: 420, height: 460)
        .background {
            Color(hexString: themeColors.background)
                .ignoresSafeArea()
        }
        .tint(themeColors.accentColor)
        .environment(\.colorScheme, themeColors.isDark ? .dark : .light)
        .task { store.send(.onAppear) }
        .alert($store.scope(state: \.alert, action: \.alert))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("Manage Teams")
                .font(.headline)
            Text("Teams in your Linear workspace")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Content

    private var contentSection: some View {
        Group {
            switch store.loadingStatus {
            case .idle, .loading:
                VStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
            case .loaded:
                teamList
            case let .failed(message):
                VStack(spacing: 12) {
                    Spacer()
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { store.send(.onAppear) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var teamList: some View {
        ScrollView(.vertical) {
            VStack(spacing: 10) {
                ForEach(store.allTeams) { team in
                    teamCard(team)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func teamCard(_ team: LinearTeam) -> some View {
        let isEnabled = store.enabledTeamIds.contains(team.id)
        let isRemoved = store.teamsToRemove.contains(team.id)
        let tint = themeColors.teamTint(colorIndex: team.colorIndex)

        return VStack(alignment: .leading, spacing: 0) {
            teamCardHeader(team: team, isEnabled: isEnabled, isRemoved: isRemoved, tint: tint)
            if isEnabled, !isRemoved {
                Divider().padding(.vertical, 8)
                teamCardIngestion(team: team)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.fill.quaternary)
        )
        .opacity(isRemoved ? 0.6 : 1.0)
    }

    private func teamCardHeader(
        team: LinearTeam, isEnabled: Bool, isRemoved: Bool, tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in store.send(.enableTeamToggled(teamId: team.id)) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .disabled(isRemoved)

            Circle().fill(tint).frame(width: 8, height: 8)

            Text(team.key)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(isRemoved ? tint.opacity(0.3) : tint)

            Text(team.name)
                .font(.callout)
                .foregroundStyle(isRemoved ? .tertiary : .primary)
                .strikethrough(isRemoved)

            Spacer(minLength: 0)

            if isRemoved {
                Text("Removed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.fill.quaternary, in: Capsule())
            } else if isEnabled {
                Button {
                    store.send(.removeTeamTapped(teamId: team.id))
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove team and delete its issues")
            }
        }
    }

    private func teamCardIngestion(team: LinearTeam) -> some View {
        HStack(spacing: 8) {
            Text("Import")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { team.ingestAllIssues },
                set: { _ in store.send(.ingestAllToggled(teamId: team.id)) }
            )) {
                Text("By label").tag(false)
                Text("All issues").tag(true)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 160)

            if !team.ingestAllIssues {
                Picker("", selection: Binding(
                    get: { team.filterLabel },
                    set: { store.send(.filterLabelChanged(teamId: team.id, label: $0)) }
                )) {
                    ForEach(store.availableLabels, id: \.self) { label in
                        Text(label).tag(label)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button("Cancel") {
                store.send(.cancelTapped)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Spacer()
            Button {
                store.send(.saveTapped)
            } label: {
                Text("Save")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!hasChanges)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var hasChanges: Bool {
        let originalEnabled = Set(
            store.allTeams.filter(\.isEnabled).map(\.id)
        )
        if store.enabledTeamIds != originalEnabled || !store.teamsToRemove.isEmpty {
            return true
        }
        return store.allTeams.contains { team in
            if team.ingestAllIssues != (store.originalIngestAllFlags[team.id] ?? false) {
                return true
            }
            if team.filterLabel != (store.originalFilterLabels[team.id] ?? "klause") {
                return true
            }
            return false
        }
    }
}
