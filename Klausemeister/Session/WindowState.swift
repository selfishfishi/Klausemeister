import AppKit
import GhosttyKit

@MainActor
@Observable
final class WindowState {
    var tabs: [TabSession] = []
    var activeTabID: UUID?
    var showSidebar: Bool = true

    var activeTab: TabSession? {
        guard let activeTabID else { return nil }
        return tabs.first { $0.id == activeTabID }
    }

    init() {
        createTab()
    }

    func createTab() {
        guard let app = GhosttyApp.shared.app else { return }
        let surfaceView = SurfaceView(frame: .zero)
        surfaceView.initializeSurface(app: app, workingDirectory: NSHomeDirectory())
        let tab = TabSession(surfaceView: surfaceView)
        tabs.append(tab)
        switchTab(id: tab.id)
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        let wasActive = (id == activeTabID)
        tabs.remove(at: index)

        if tabs.isEmpty {
            createTab()
            return
        }

        if wasActive {
            let newIndex = min(index, tabs.count - 1)
            switchTab(id: tabs[newIndex].id)
        }
    }

    func switchTab(id: UUID) {
        guard let newTab = tabs.first(where: { $0.id == id }) else { return }

        if let oldTab = activeTab, oldTab.id != id {
            ghostty_surface_set_focus(oldTab.surfaceView.surface, false)
        }

        activeTabID = id

        requestFocus(for: newTab.surfaceView)
    }

    func selectPreviousTab() {
        guard let activeTabID,
              let index = tabs.firstIndex(where: { $0.id == activeTabID }),
              tabs.count > 1 else { return }
        let newIndex = (index - 1 + tabs.count) % tabs.count
        switchTab(id: tabs[newIndex].id)
    }

    func selectNextTab() {
        guard let activeTabID,
              let index = tabs.firstIndex(where: { $0.id == activeTabID }),
              tabs.count > 1 else { return }
        let newIndex = (index + 1) % tabs.count
        switchTab(id: tabs[newIndex].id)
    }

    func selectTab(at position: Int) {
        guard position >= 1, position <= tabs.count else { return }
        switchTab(id: tabs[position - 1].id)
    }

    // MARK: - Focus Transfer

    private func requestFocus(for surfaceView: SurfaceView, attempt: Int = 0) {
        guard let window = surfaceView.window else {
            if attempt < 50 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                    self?.requestFocus(for: surfaceView, attempt: attempt + 1)
                }
            }
            return
        }
        window.makeFirstResponder(surfaceView)
    }
}
