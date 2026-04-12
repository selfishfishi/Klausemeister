import SwiftUI

/// Linear flow layout for a worktree's inbox / processing / outbox.
///
/// Queued issues sit as small pills on the left, the active processing
/// issue fills a prominent center box with identifier and title, and
/// completed issues trail off as dim pills on the right. Each of the
/// three logical zones is still an independent drop target.
struct SwimlaneBarRow: View {
    let worktree: Worktree
    var teamFor: ((_ issueId: String) -> LinearTeam?)?
    var onMarkComplete: (() -> Void)?
    var onReturnToMeister: ((_ issueId: String) -> Void)?
    var onDropToInbox: ((_ issueId: String) -> Void)?
    var onDropToProcessing: ((_ issueId: String) -> Void)?
    var onDropToOutbox: ((_ issueId: String) -> Void)?

    @State private var inboxTargeted = false
    @State private var processingTargeted = false
    @State private var outboxTargeted = false

    @Environment(\.themeColors) private var themeColors

    private let queuedTint: Color = MeisterState.todo.tint
    private let activeTint: Color = MeisterState.inProgress.tint
    private let doneTint: Color = MeisterState.inReview.tint

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            inboxSection
            processingSection
            outboxSection
        }
    }

    // MARK: - Sections

    private var inboxSection: some View {
        HStack(spacing: 5) {
            ForEach(worktree.inbox, id: \.id) { issue in
                queuedPill(issue)
            }
        }
        .frame(minWidth: 32, minHeight: 34, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(targetingRing(isOn: inboxTargeted, tint: queuedTint))
        .animation(.easeInOut(duration: 0.15), value: inboxTargeted)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first, let onDropToInbox else { return false }
            onDropToInbox(id)
            return true
        } isTargeted: { targeted in
            inboxTargeted = targeted
        }
    }

    private var processingSection: some View {
        ZStack {
            if let processing = worktree.processing {
                activeBox(processing)
            } else {
                idlePlaceholder
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .overlay(targetingRing(isOn: processingTargeted, tint: activeTint))
        .animation(.easeInOut(duration: 0.15), value: processingTargeted)
        .dropDestination(for: String.self) { items, _ in
            guard worktree.processing == nil,
                  let id = items.first,
                  let onDropToProcessing
            else { return false }
            onDropToProcessing(id)
            return true
        } isTargeted: { targeted in
            processingTargeted = targeted && worktree.processing == nil
        }
    }

    private var outboxSection: some View {
        HStack(spacing: 5) {
            ForEach(worktree.outbox, id: \.id) { issue in
                donePill(issue)
            }
        }
        .frame(minWidth: 32, minHeight: 34, alignment: .trailing)
        .contentShape(Rectangle())
        .overlay(targetingRing(isOn: outboxTargeted, tint: doneTint))
        .animation(.easeInOut(duration: 0.15), value: outboxTargeted)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first, let onDropToOutbox else { return false }
            onDropToOutbox(id)
            return true
        } isTargeted: { targeted in
            outboxTargeted = targeted
        }
    }

    // MARK: - Pills

    private func queuedPill(_ issue: LinearIssue) -> some View {
        HStack(spacing: 3) {
            if let team = teamFor?(issue.id) {
                teamKeyLabel(team, opacity: 0.85)
            }
            Text(issue.identifier)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(queuedTint.opacity(0.85))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(queuedTint.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(queuedTint.opacity(0.45), lineWidth: 0.75)
        )
        .draggable(issue.id)
        .contextMenu {
            if let onReturnToMeister {
                Button("Return to Meister") { onReturnToMeister(issue.id) }
            }
        }
    }

    private func donePill(_ issue: LinearIssue) -> some View {
        HStack(spacing: 3) {
            if let team = teamFor?(issue.id) {
                teamKeyLabel(team, opacity: 0.55)
            }
            Text(issue.identifier)
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .foregroundStyle(doneTint.opacity(0.55))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(doneTint.opacity(0.08))
        )
        .draggable(issue.id)
        .contextMenu {
            if let onReturnToMeister {
                Button("Return to Meister") { onReturnToMeister(issue.id) }
            }
        }
    }

    private func activeBox(_ issue: LinearIssue) -> some View {
        HStack(spacing: 10) {
            if let team = teamFor?(issue.id) {
                teamKeyLabel(team, opacity: 1.0)
            }
            Text(issue.identifier)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(activeTint)
            Text(issue.title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if issue.isOrphaned {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(activeTint.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(activeTint.opacity(0.65), lineWidth: 1.2)
        )
        .draggable(issue.id)
        .contextMenu {
            if let onMarkComplete {
                Button("Mark as Done") { onMarkComplete() }
            }
            if let onReturnToMeister {
                Button("Return to Meister") { onReturnToMeister(issue.id) }
            }
        }
    }

    private var idlePlaceholder: some View {
        Text("— idle —")
            .font(.footnote.italic())
            .foregroundStyle(.secondary.opacity(0.5))
            .frame(maxWidth: .infinity, minHeight: 34)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        Color.secondary.opacity(0.22),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            )
    }

    private func targetingRing(isOn: Bool, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(tint.opacity(isOn ? 0.7 : 0), lineWidth: 2)
    }

    // MARK: - Team badge helper

    private func teamKeyLabel(_ team: LinearTeam, opacity: Double) -> some View {
        let color = themeColors.teamTint(colorIndex: team.colorIndex)
        return Text(team.key)
            .font(.system(.caption2, design: .monospaced).weight(.bold))
            .foregroundStyle(color.opacity(opacity))
    }
}
