// Klausemeister/Workflow/ProductStateMachine.swift
import Foundation

/// A slash command that drives state transitions in the product state machine.
///
/// Each command maps to exactly one transition with preconditions on the
/// current `ProductState`. Commands that mutate worktree state: `.pull`,
/// `.push`. All others mutate kanban state only.
enum WorkflowCommand: String, CaseIterable, Equatable, Hashable {
    case define
    case execute
    case review
    case openPR
    case babysit
    case complete
    case pull
    case push

    /// Human-readable verb for button labels and menus.
    var verbLabel: String {
        switch self {
        case .define: "Define"
        case .execute: "Execute"
        case .review: "Review"
        case .openPR: "Open PR"
        case .babysit: "Babysit"
        case .complete: "Complete"
        case .pull: "Pull"
        case .push: "Push"
        }
    }

    /// The literal slash command the meister Claude Code recognises for this
    /// transition, or `nil` for machine-internal commands with no user-facing
    /// equivalent. Used by the swimlane UI to inject via `tmux send-keys`.
    ///
    /// `.complete` is internal — it's applied by `/klause-open-pr` when the
    /// branch has no commits, and there's no direct `/klause-complete` skill.
    var slashCommand: String? {
        switch self {
        case .define: "/klause-define"
        case .execute: "/klause-execute"
        case .review: "/klause-review"
        case .openPR: "/klause-open-pr"
        case .babysit: "/klause-babysit"
        case .pull: "/klause-pull"
        case .push: "/klause-push"
        case .complete: nil
        }
    }
}

/// The product state: a pair of kanban (ticket lifecycle) and worktree
/// (physical workspace) positions.
///
/// Only 9 of the 18 possible combinations are reachable from the initial
/// state `(backlog, inbox)` via legal transitions. The transition function
/// enforces this — unreachable pairs cannot be produced by `applying(_:)`.
struct ProductState: Equatable, Hashable {
    var kanban: MeisterState
    var queue: QueuePosition

    /// The initial state for a newly imported issue assigned to a worktree.
    static let initial = ProductState(kanban: .backlog, queue: .inbox)
}

// MARK: - Transition table

/// A single row in the transition table: given `from` state and `command`,
/// the machine moves to `result`.
private struct Transition {
    let from: ProductState
    let command: WorkflowCommand
    let result: ProductState
}

/// Transitions not in this table are illegal and `applying(_:)` returns `nil`.
private let transitions: [Transition] = [
    // pull: Inbox → Processing (kanban unchanged)
    .init(from: .init(kanban: .backlog, queue: .inbox), command: .pull, result: .init(kanban: .backlog, queue: .processing)),
    .init(from: .init(kanban: .todo, queue: .inbox), command: .pull, result: .init(kanban: .todo, queue: .processing)),

    // define: Backlog → Todo (queue unchanged)
    .init(from: .init(kanban: .backlog, queue: .inbox), command: .define, result: .init(kanban: .todo, queue: .inbox)),
    .init(from: .init(kanban: .backlog, queue: .processing), command: .define, result: .init(kanban: .todo, queue: .processing)),

    // execute: Todo/Processing → InProgress/Processing
    .init(from: .init(kanban: .todo, queue: .processing), command: .execute, result: .init(kanban: .inProgress, queue: .processing)),

    // review: InProgress/Processing → InReview/Processing (manual-only, skipped by nextCommand)
    .init(from: .init(kanban: .inProgress, queue: .processing), command: .review, result: .init(kanban: .inReview, queue: .processing)),

    // openPR: (InProgress | InReview)/Processing → Testing/Processing
    .init(from: .init(kanban: .inProgress, queue: .processing), command: .openPR, result: .init(kanban: .testing, queue: .processing)),
    .init(from: .init(kanban: .inReview, queue: .processing), command: .openPR, result: .init(kanban: .testing, queue: .processing)),

    // babysit: Testing/Processing → Completed/Processing
    .init(from: .init(kanban: .testing, queue: .processing), command: .babysit, result: .init(kanban: .completed, queue: .processing)),

    // complete: (InProgress | InReview)/Processing → Completed/Processing (no-PR path for audits/research)
    .init(from: .init(kanban: .inProgress, queue: .processing), command: .complete, result: .init(kanban: .completed, queue: .processing)),
    .init(from: .init(kanban: .inReview, queue: .processing), command: .complete, result: .init(kanban: .completed, queue: .processing)),

    // push: Completed/Processing → Completed/Outbox
    .init(from: .init(kanban: .completed, queue: .processing), command: .push, result: .init(kanban: .completed, queue: .outbox))
]

// MARK: - Transition function

extension ProductState {
    /// Apply a command to this state, returning the new state if the
    /// transition is legal, or `nil` if the command's preconditions are
    /// not met.
    ///
    /// This is a pure function with no side effects. Reducers call it to
    /// guard and compute state changes; the MCP layer calls it to validate
    /// transition requests from child Claude sessions.
    func applying(_ command: WorkflowCommand) -> ProductState? {
        transitions.first { $0.from == self && $0.command == command }?.result
    }
}

// MARK: - Dispatch table for /klause:next

extension ProductState {
    /// The command that `/klause:next` should invoke for this state,
    /// or `nil` if the state is terminal or unreachable.
    ///
    /// `.review` is intentionally absent — it is a manual-only command
    /// that users invoke explicitly via `/klause:review`. The default
    /// path skips review and goes straight from In Progress to open-pr.
    ///
    /// Exhaustive over both enums so the compiler enforces coverage when
    /// new cases are added.
    var nextCommand: WorkflowCommand? {
        switch (kanban, queue) {
        // --- 9 reachable product states ---
        case (.backlog, .inbox): .pull
        case (.backlog, .processing): .define
        case (.todo, .inbox): .pull
        case (.todo, .processing): .execute
        case (.inProgress, .processing): .openPR
        case (.inReview, .processing): .openPR
        case (.testing, .processing): .babysit
        case (.completed, .processing): .push
        case (.completed, .outbox): nil
        // --- unreachable combinations (no transition produces these) ---
        case (.backlog, .outbox): nil
        case (.todo, .outbox): nil
        case (.inProgress, .inbox): nil
        case (.inProgress, .outbox): nil
        case (.inReview, .inbox): nil
        case (.inReview, .outbox): nil
        case (.testing, .inbox): nil
        case (.testing, .outbox): nil
        case (.completed, .inbox): nil
        }
    }

    /// All commands whose preconditions are currently satisfied.
    var validCommands: [WorkflowCommand] {
        WorkflowCommand.allCases.filter { applying($0) != nil }
    }

    /// Whether this state is already the result of applying `command`.
    /// Used by the MCP layer for idempotent transition handling — if
    /// we're already at the result state, the command was already applied.
    func isResultOf(_ command: WorkflowCommand) -> Bool {
        transitions.contains { $0.command == command && $0.result == self }
    }

    /// Whether this is the terminal state — no further transitions possible.
    var isComplete: Bool {
        kanban == .completed && queue == .outbox
    }
}
