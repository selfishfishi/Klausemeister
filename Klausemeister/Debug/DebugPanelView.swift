import ComposableArchitecture
import SwiftUI

struct DebugPanelView: View {
    let store: StoreOf<DebugPanelFeature>
    let worktrees: [Worktree]

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                diagnosticsSection
                shimProcessesSection
                worktreeConnectionsSection
                eventLogSection
            }
            .padding(20)
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 400, idealHeight: 500)
        .background(Color(hexString: themeColors.background))
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Text("MCP Debug Panel")
                .font(.title2.weight(.semibold))
            Spacer()
            Button {
                store.send(.refreshTapped)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("System")
                .font(.headline)
            HStack(spacing: 12) {
                diagnosticBadge(
                    label: "Socket",
                    value: store.socketExists ? "Active" : "Missing",
                    isGood: store.socketExists
                )
                diagnosticBadge(
                    label: "Shim Symlink",
                    value: store.shimSymlinkTarget.isEmpty
                        ? "Not set" : abbreviatePath(store.shimSymlinkTarget),
                    isGood: !store.shimSymlinkTarget.isEmpty
                )
            }
        }
    }

    private func diagnosticBadge(label: String, value: String, isGood: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isGood ? themeColors.accentColor : themeColors.errorColor)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Shim Processes

    private var shimProcessesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shim Processes")
                .font(.headline)
            if store.shimStates.isEmpty {
                Text("No state files found")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(store.shimStates) { shim in
                    shimRow(shim)
                }
            }
        }
    }

    private func shimRow(_ shim: ShimStateInfo) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(shim.isAlive ? themeColors.accentColor : themeColors.errorColor)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("PID \(shim.pid)")
                        .font(.caption.monospaced().weight(.semibold))
                    Text(shim.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !shim.isAlive {
                        Text("DEAD")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(themeColors.errorColor)
                    }
                }
                Text(shim.worktreeId)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Text(shim.timestamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(8)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Worktree Connections

    private var worktreeConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Worktree Connections")
                .font(.headline)
            if worktrees.isEmpty {
                Text("No worktrees")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(worktrees) { worktree in
                    worktreeRow(worktree)
                }
            }
        }
    }

    private func worktreeRow(_ worktree: Worktree) -> some View {
        HStack(spacing: 8) {
            MeisterStatusDot(status: worktree.meisterStatus)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(worktree.name)
                        .font(.caption.weight(.semibold))
                    Text(meisterStatusLabel(worktree.meisterStatus))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(tmuxStatusLabel(worktree.tmuxSessionStatus))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(worktree.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(8)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Event Log

    private var eventLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Event Log (\(store.events.count))")
                .font(.headline)
            if store.events.isEmpty {
                Text("No events yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(store.events) { event in
                    eventRow(event)
                }
            }
        }
    }

    private func eventRow(_ event: DebugPanelFeature.DebugEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(formatTime(event.timestamp))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .leading)
            Text(event.description)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    // MARK: - Helpers

    private func meisterStatusLabel(_ status: MeisterStatus) -> String {
        switch status {
        case .none: "none"
        case .spawning: "spawning"
        case .running: "running"
        case .disconnected: "disconnected"
        }
    }

    private func tmuxStatusLabel(_ status: TmuxSessionStatus) -> String {
        switch status {
        case .unknown: "tmux:?"
        case .sessionExists: "tmux:yes"
        case .needsCreation: "tmux:no"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private func formatTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private func abbreviatePath(_ path: String) -> String {
        let components = path.split(separator: "/")
        guard components.count > 3 else { return path }
        return ".../" + components.suffix(3).joined(separator: "/")
    }
}
