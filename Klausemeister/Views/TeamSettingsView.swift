import ComposableArchitecture
import SwiftUI

struct TeamSettingsView: View {
    @Bindable var store: StoreOf<TeamSettingsFeature>

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().padding(.horizontal, 16)
            contentSection
            Divider().padding(.horizontal, 16)
            footerSection
        }
        .frame(width: 460, height: 480)
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
                .foregroundStyle(.primary)
            Text("Teams in your Linear workspace")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
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
            VStack(spacing: 2) {
                ForEach(store.allTeams) { team in
                    teamRow(team)
                }
            }
            .padding(6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // swiftlint:disable:next function_body_length
    private func teamRow(_ team: LinearTeam) -> some View {
        let isEnabled = store.enabledTeamIds.contains(team.id)
        let isRemoved = store.teamsToRemove.contains(team.id)
        let tint = themeColors.teamTint(colorIndex: team.colorIndex)

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(team.key)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 48, alignment: .leading)
                Text(team.name)
                    .font(.callout)
                    .foregroundStyle(isRemoved ? .tertiary : .primary)
                    .strikethrough(isRemoved)
                Spacer(minLength: 0)
                if isRemoved {
                    Text("Removed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    if isEnabled {
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
                    Button {
                        store.send(.enableTeamToggled(teamId: team.id))
                    } label: {
                        Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                            .font(.body)
                            .foregroundStyle(isEnabled ? tint : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if isEnabled, !isRemoved {
                HStack(spacing: 10) {
                    Toggle("All issues", isOn: Binding(
                        get: { team.ingestAllIssues },
                        set: { _ in store.send(.ingestAllToggled(teamId: team.id)) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()

                    Text(team.ingestAllIssues ? "All issues" : "Label only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)

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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isEnabled && !isRemoved ? tint.opacity(0.08) : .clear)
        )
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
