import SwiftUI

struct TeamPickerView: View {
    let teams: [LinearTeam]
    let selectedTeamIds: Set<String>
    let onToggle: (String) -> Void
    let onConfirm: () -> Void

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                headerSection
                teamList
                confirmButton
            }
            .frame(maxWidth: 400)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Select Teams")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Choose which Linear teams to sync")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Team List

    private var teamList: some View {
        VStack(spacing: 2) {
            ForEach(teams) { team in
                teamRow(team)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }

    private func teamRow(_ team: LinearTeam) -> some View {
        let isSelected = selectedTeamIds.contains(team.id)
        let tint = themeColors.teamTint(colorIndex: team.colorIndex)

        return Button { onToggle(team.id) } label: {
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
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(isSelected ? tint : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Confirm

    private var confirmButton: some View {
        Button(action: onConfirm) {
            Text("Continue")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(hexString: themeColors.background))
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(themeColors.accentColor, in: RoundedRectangle(cornerRadius: 10))
                .shadow(color: themeColors.accentColor.opacity(0.3 * themeColors.glowIntensity), radius: 12)
        }
        .buttonStyle(.plain)
        .disabled(selectedTeamIds.isEmpty)
        .opacity(selectedTeamIds.isEmpty ? 0.5 : 1.0)
    }
}
