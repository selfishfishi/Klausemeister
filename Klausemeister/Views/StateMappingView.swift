import ComposableArchitecture
import SwiftUI

struct StateMappingView: View {
    @Bindable var store: StoreOf<StateMappingFeature>

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().padding(.horizontal, 16)
            if store.teams.count > 1 {
                teamPicker
                Divider().padding(.horizontal, 16)
            }
            contentSection
            Divider().padding(.horizontal, 16)
            footerSection
        }
        .frame(width: 480, height: 520)
        .background {
            Color(hexString: themeColors.background)
                .ignoresSafeArea()
        }
        .tint(themeColors.accentColor)
        .task { store.send(.onAppear) }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("Stage Mappings")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Assign Linear states to kanban stages")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
    }

    // MARK: - Team Picker

    private var teamPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.teams) { team in
                    let isSelected = store.selectedTeamId == team.id
                    let tint = themeColors.teamTint(colorIndex: team.colorIndex)
                    Button {
                        store.send(.teamSelected(team.id))
                    } label: {
                        Text(team.key)
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(isSelected ? tint : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? tint.opacity(0.12) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Content

    private var contentSection: some View {
        Group {
            if let teamId = store.selectedTeamId,
               let states = store.workflowStatesByTeam[teamId]
            {
                stateList(teamId: teamId, states: states)
            } else {
                VStack {
                    Spacer()
                    Text("No team selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stateList(teamId: String, states: [LinearWorkflowState]) -> some View {
        // Exclude canceled states — they are intentionally not mapped to the kanban
        let mappableStates = states.filter { $0.type != "canceled" }
        return ScrollView(.vertical) {
            VStack(spacing: 2) {
                ForEach(mappableStates) { linearState in
                    stateRow(teamId: teamId, linearState: linearState)
                }
            }
            .padding(6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func stateRow(teamId: String, linearState: LinearWorkflowState) -> some View {
        let current = store.mappings[teamId]?[linearState.id]
            ?? MeisterState.defaultMapping(for: linearState)
            ?? .backlog

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(linearState.name)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Text(linearState.type)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("", selection: Binding(
                get: { current },
                set: { store.send(.mappingChanged(
                    teamId: teamId, linearStateId: linearState.id, meisterState: $0
                )) }
            )) {
                ForEach(MeisterState.allCases) { stage in
                    Text(stage.displayName).tag(stage)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 140)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 6) {
            if let error = store.saveError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
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
        }
        .padding(.vertical, 12)
    }

    private var hasChanges: Bool {
        store.mappings != store.originalMappings
    }
}
