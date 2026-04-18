// Klausemeister/WorktreeSwitcher/WorktreeSwitcherFeature.swift
import ComposableArchitecture
import Foundation

@Reducer
struct WorktreeSwitcherFeature {
    @ObservableState
    struct State: Equatable {
        var query: String = ""
        var items: [SwitcherItem] = []
        var selectedIndex: Int = 0

        init(worktrees: [Worktree]) {
            var result: [SwitcherItem] = [.meister]
            for worktree in worktrees {
                result.append(.worktree(
                    worktreeId: worktree.id,
                    name: worktree.name,
                    branch: worktree.currentBranch
                ))
            }
            items = result
        }

        init() {}
    }

    enum SwitcherItem: Equatable, Identifiable {
        case meister
        case worktree(worktreeId: String, name: String, branch: String?)

        var id: String {
            switch self {
            case .meister: "meister"
            case let .worktree(worktreeId, _, _): worktreeId
            }
        }

        var name: String {
            switch self {
            case .meister: "Meister"
            case let .worktree(_, name, _): name
            }
        }

        var branch: String? {
            switch self {
            case .meister: nil
            case let .worktree(_, _, branch): branch
            }
        }

        var icon: String {
            switch self {
            case .meister: "squares.leading.rectangle"
            case .worktree: "arrow.triangle.branch"
            }
        }
    }

    enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        case moveUp
        case moveDown
        case confirmSelection
        case numberPressed(Int)
        case dismiss
        case delegate(Delegate)

        // swiftlint:disable:next nesting
        enum Delegate: Equatable {
            case itemSelected(SwitcherItem)
            case dismissed
        }
    }

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding(\.query):
                state.selectedIndex = 0
                return .none

            case .moveUp:
                if state.selectedIndex > 0 { state.selectedIndex -= 1 }
                return .none

            case .moveDown:
                let maxIndex = state.filteredItems.count - 1
                if state.selectedIndex < maxIndex { state.selectedIndex += 1 }
                return .none

            case .confirmSelection:
                let filtered = state.filteredItems
                guard state.selectedIndex < filtered.count else { return .none }
                return .send(.delegate(.itemSelected(filtered[state.selectedIndex])))

            case let .numberPressed(number):
                let index = number - 1
                let filtered = state.filteredItems
                guard index >= 0, index < filtered.count else { return .none }
                return .send(.delegate(.itemSelected(filtered[index])))

            case .dismiss:
                return .send(.delegate(.dismissed))

            case .delegate, .binding:
                return .none
            }
        }
    }
}

// MARK: - Derived State

extension WorktreeSwitcherFeature.State {
    var filteredItems: [WorktreeSwitcherFeature.SwitcherItem] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !search.isEmpty else { return items }
        return items.filter { item in
            item.name.lowercased().contains(search)
                || (item.branch?.lowercased().contains(search) ?? false)
        }
    }
}
