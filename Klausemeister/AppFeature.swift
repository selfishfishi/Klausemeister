import ComposableArchitecture
import Foundation

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var tabs: IdentifiedArrayOf<Tab> = []
        var activeTabID: UUID?
        var showSidebar: Bool = true

        struct Tab: Equatable, Identifiable {
            let id: UUID
            var title: String = "Terminal"
        }
    }

    enum Action {
        case onAppear
        case newTabButtonTapped
        case closeTabButtonTapped(UUID)
        case tabSelected(UUID)
        case previousTabShortcutPressed
        case nextTabShortcutPressed
        case tabShortcutPressed(position: Int)
        case sidebarTogglePressed
        case surfaceCreated(id: UUID)
        case surfaceCreationFailed(id: UUID)
    }

    @Dependency(\.surfaceManager) var surfaceManager
    @Dependency(\.uuid) var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.newTabButtonTapped)

            case .newTabButtonTapped:
                let id = uuid()
                state.tabs.append(State.Tab(id: id))
                state.activeTabID = id
                return .run { [id] send in
                    let success = surfaceManager.createSurface(id)
                    if success {
                        await send(.surfaceCreated(id: id))
                    } else {
                        await send(.surfaceCreationFailed(id: id))
                    }
                }

            case let .surfaceCreated(id):
                return .run { _ in
                    _ = await surfaceManager.focus(id)
                }

            case let .surfaceCreationFailed(id):
                state.tabs.remove(id: id)
                state.activeTabID = state.tabs.last?.id
                return .none

            case let .closeTabButtonTapped(id):
                guard let index = state.tabs.index(id: id) else {
                    return .none
                }
                let wasActive = (id == state.activeTabID)
                state.tabs.remove(id: id)

                if state.tabs.isEmpty {
                    return .merge(
                        .run { _ in surfaceManager.destroySurface(id) },
                        .send(.newTabButtonTapped)
                    )
                }

                if wasActive {
                    let newIndex = min(index, state.tabs.count - 1)
                    let newID = state.tabs[newIndex].id
                    state.activeTabID = newID
                    return .run { [id, newID] _ in
                        surfaceManager.destroySurface(id)
                        _ = await surfaceManager.focus(newID)
                    }
                }

                return .run { _ in
                    surfaceManager.destroySurface(id)
                }

            case let .tabSelected(id):
                guard state.tabs[id: id] != nil,
                      id != state.activeTabID else { return .none }
                let oldID = state.activeTabID
                state.activeTabID = id
                return .run { [oldID] _ in
                    if let oldID { surfaceManager.unfocus(oldID) }
                    _ = await surfaceManager.focus(id)
                }

            case .previousTabShortcutPressed:
                guard let activeTabID = state.activeTabID,
                      let index = state.tabs.index(id: activeTabID),
                      state.tabs.count > 1 else { return .none }
                let newIndex = (index - 1 + state.tabs.count) % state.tabs.count
                return .send(.tabSelected(state.tabs[newIndex].id))

            case .nextTabShortcutPressed:
                guard let activeTabID = state.activeTabID,
                      let index = state.tabs.index(id: activeTabID),
                      state.tabs.count > 1 else { return .none }
                let newIndex = (index + 1) % state.tabs.count
                return .send(.tabSelected(state.tabs[newIndex].id))

            case let .tabShortcutPressed(position):
                guard position >= 1, position <= state.tabs.count else {
                    return .none
                }
                return .send(.tabSelected(state.tabs[position - 1].id))

            case .sidebarTogglePressed:
                state.showSidebar.toggle()
                return .none
            }
        }
    }
}

extension AppFeature.State {
    var activeTab: Tab? {
        guard let activeTabID else { return nil }
        return tabs[id: activeTabID]
    }
}
