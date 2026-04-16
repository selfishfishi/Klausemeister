import SwiftUI

/// Linear flow layout for a worktree's inbox / processing / outbox.
///
/// Queued issues sit as small pills on the left, the active processing
/// issue fills a prominent center box with identifier and title, and
/// completed issues trail off as dim pills on the right. Each of the
/// three logical zones is still an independent drop target.
struct SwimlaneBarRow: View {
    let worktree: Worktree
    var onMarkComplete: (() -> Void)?
    var onReturnToMeister: ((_ issueId: String) -> Void)?
    var onSelectIssue: ((_ issueId: String) -> Void)?
    /// Inject a fully-qualified slash command (e.g. `"/klause-workflow:klause-next"`)
    /// into the meister's tmux session. Commands must include the plugin
    /// namespace because the meister's Claude Code only resolves short
    /// forms for user-typed input, not injected input.
    var onSendSlashCommand: ((_ slashCommand: String) -> Void)?
    /// Kanban-style state jump for the active issue — Linear-only move, does
    /// not invoke any `/klause-*` command.
    var onMoveIssueStatus: ((_ issueId: String, _ target: MeisterState) -> Void)?

    @Environment(\.keyBindings) private var bindings
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(worktree.inbox.reversed(), id: \.id) { issue in
                    queuedPill(issue)
                }
            }
            .frame(minHeight: 34)
        }
        .defaultScrollAnchor(.trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(worktree.outbox, id: \.id) { issue in
                    donePill(issue)
                }
            }
            .frame(minHeight: 34)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .contentShape(Rectangle())
        .onTapGesture { onSelectIssue?(issue.id) }
        .draggable(issue.id)
        .contextMenu {
            if let onReturnToMeister {
                Button("Return to Meister") { onReturnToMeister(issue.id) }
                    .keyboardShortcut(for: .returnIssueToMeister, in: bindings)
            }
        }
    }

    private func donePill(_ issue: LinearIssue) -> some View {
        HStack(spacing: 3) {
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
        .contentShape(Rectangle())
        .onTapGesture { onSelectIssue?(issue.id) }
        .draggable(issue.id)
        .contextMenu {
            if let onReturnToMeister {
                Button("Return to Meister") { onReturnToMeister(issue.id) }
                    .keyboardShortcut(for: .returnIssueToMeister, in: bindings)
            }
        }
    }

    private func activeBox(_ issue: LinearIssue) -> some View {
        let productState = issue.meisterState.map { ProductState(kanban: $0, queue: .processing) }
        let validCommands = productState?.validCommands ?? []

        return HStack(spacing: 10) {
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
        .contentShape(Rectangle())
        .onTapGesture { onSelectIssue?(issue.id) }
        .draggable(issue.id)
        .contextMenu { activeContextMenu(issue: issue, validCommands: validCommands) }
    }

    @ViewBuilder
    private func activeContextMenu(
        issue: LinearIssue,
        validCommands: [WorkflowCommand]
    ) -> some View {
        if let onSendSlashCommand {
            Button("Next (/klause-next)") {
                onSendSlashCommand("/klause-workflow:klause-next")
            }
        }
        let runnable = validCommands.compactMap { cmd -> (WorkflowCommand, String)? in
            guard let slash = cmd.slashCommand else { return nil }
            return (cmd, slash)
        }
        if !runnable.isEmpty, let onSendSlashCommand {
            Menu("Run command") {
                ForEach(runnable, id: \.0) { pair in
                    Button(pair.0.verbLabel) { onSendSlashCommand(pair.1) }
                }
            }
        }
        if let onMoveIssueStatus {
            Menu("Move to…") {
                ForEach(MeisterState.allCases.filter { $0 != issue.meisterState }) { target in
                    Button(target.displayName) {
                        onMoveIssueStatus(issue.id, target)
                    }
                }
            }
        }
        Divider()
        if let onMarkComplete {
            Button("Mark as Done") { onMarkComplete() }
                .keyboardShortcut(for: .markIssueDone, in: bindings)
        }
        if let onReturnToMeister {
            Button("Return to Meister") { onReturnToMeister(issue.id) }
                .keyboardShortcut(for: .returnIssueToMeister, in: bindings)
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
}
