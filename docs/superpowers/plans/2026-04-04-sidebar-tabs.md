# Sidebar with Multiple Terminal Tabs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a sidebar with create/switch/close for multiple terminal sessions, replacing the single-terminal layout.

**Architecture:** SwiftUI outer shell (sidebar list + container) wrapping an AppKit NSView-based terminal content area. `WindowState` (`@Observable`) owns the tab array and operations. `TerminalContentView` (`NSViewRepresentable`) manages a container NSView that swaps child SurfaceViews when the active tab changes. Focus transfer follows Calyx's async-retry pattern.

**Tech Stack:** Swift, SwiftUI, AppKit, Observation framework (`@Observable`), GhosttyKit C API

**Spec:** `docs/superpowers/specs/2026-04-04-sidebar-tabs-design.md`

**Note on testing:** This project has no test infrastructure. Each task verifies via `xcodebuild` compilation. Manual verification criteria are listed in Task 8.

**Note on Xcode project:** The `Klausemeister/` directory uses `fileSystemSynchronizedGroups` — Xcode auto-discovers new `.swift` files. No pbxproj edits needed.

---

## File Structure

| Action | File | Responsibility |
| --- | --- | --- |
| Create | `Klausemeister/Session/TabSession.swift` | Single tab's identity and owned SurfaceView |
| Create | `Klausemeister/Session/WindowState.swift` | Tab array, active tab tracking, create/close/switch operations, focus transfer |
| Create | `Klausemeister/Views/SidebarView.swift` | SwiftUI list of tabs with create/close/click-to-switch |
| Create | `Klausemeister/Views/TerminalContentView.swift` | NSViewRepresentable: container NSView that swaps child SurfaceViews |
| Modify | `Klausemeister/Terminal/SurfaceView.swift` | Remove auto-focus from `viewDidMoveToWindow()` |
| Modify | `Klausemeister/TerminalContainerView.swift` | Rewrite: HStack with sidebar + terminal content + keyboard shortcuts |
| Modify | `Klausemeister/KlausemeisterApp.swift` | Create WindowState, add `.commands` for keyboard shortcuts |

---

### Task 1: Remove auto-focus from SurfaceView

**Files:**
- Modify: `Klausemeister/Terminal/SurfaceView.swift:85-90`

- [ ] **Step 1: Edit `viewDidMoveToWindow`**

In `Klausemeister/Terminal/SurfaceView.swift`, replace the `viewDidMoveToWindow` method:

```swift
// Before:
override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window != nil {
        window?.makeFirstResponder(self)
    }
}

// After:
override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
}
```

The focus transfer protocol in `WindowState.switchTab()` (Task 3) will be the sole owner of first responder management. The `becomeFirstResponder()` / `resignFirstResponder()` callbacks that call `setFocus()` remain unchanged.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Klausemeister/Terminal/SurfaceView.swift
git commit -m "Remove auto-focus from viewDidMoveToWindow for tab switching"
```

---

### Task 2: Create TabSession data model

**Files:**
- Create: `Klausemeister/Session/TabSession.swift`

- [ ] **Step 1: Create the Session directory**

```bash
mkdir -p Klausemeister/Session
```

- [ ] **Step 2: Write TabSession**

Create `Klausemeister/Session/TabSession.swift`:

```swift
import Foundation

@MainActor
@Observable
final class TabSession: Identifiable {
    let id = UUID()
    var title: String = "Terminal"
    let surfaceView: SurfaceView

    init(surfaceView: SurfaceView) {
        self.surfaceView = surfaceView
    }
}
```

Key points:
- `@Observable` (Swift Observation framework) — SwiftUI will react to `title` changes.
- `surfaceView` is `let` — a tab always owns one surface for its lifetime.
- `Identifiable` for SwiftUI `ForEach` usage.
- `@MainActor` because SurfaceView is an NSView (must be accessed on main thread).

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Klausemeister/Session/TabSession.swift
git commit -m "Add TabSession data model"
```

---

### Task 3: Create WindowState with tab operations

**Files:**
- Create: `Klausemeister/Session/WindowState.swift`

- [ ] **Step 1: Write WindowState**

Create `Klausemeister/Session/WindowState.swift`:

```swift
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
            // Prefer the tab now at the same index (next), fall back to previous
            let newIndex = min(index, tabs.count - 1)
            switchTab(id: tabs[newIndex].id)
        }
    }

    func switchTab(id: UUID) {
        guard let newTab = tabs.first(where: { $0.id == id }) else { return }

        // Unfocus old surface
        if let oldTab = activeTab, oldTab.id != id {
            ghostty_surface_set_focus(oldTab.surfaceView.surface, false)
        }

        activeTabID = id

        // Focus transfer: async retry until the view is in the hierarchy
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
            // View not in hierarchy yet — retry up to 500ms (50 attempts * 10ms)
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
```

Key points:
- `createTab()` is called in `init()` to ensure the app always starts with one tab.
- `closeTab()` never leaves `tabs` empty — if the last tab is closed, a new one is created.
- `switchTab()` explicitly unfocuses the old surface, then triggers async focus transfer.
- `requestFocus()` retries `makeFirstResponder` at 10ms intervals for up to 500ms. `becomeFirstResponder()` on SurfaceView automatically calls `ghostty_surface_set_focus(true)`.
- `selectPreviousTab()` / `selectNextTab()` wrap around.
- `selectTab(at:)` uses 1-based indexing (for Cmd+1 through Cmd+9).

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Klausemeister/Session/WindowState.swift
git commit -m "Add WindowState with tab create/close/switch and focus transfer"
```

---

### Task 4: Create TerminalContentView

**Files:**
- Create: `Klausemeister/Views/TerminalContentView.swift`

- [ ] **Step 1: Create the Views directory**

```bash
mkdir -p Klausemeister/Views
```

- [ ] **Step 2: Write TerminalContentView**

Create `Klausemeister/Views/TerminalContentView.swift`:

```swift
import AppKit
import SwiftUI

struct TerminalContentView: NSViewRepresentable {
    let surfaceView: SurfaceView?
    let activeTabID: UUID?

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.autoresizesSubviews = true
        if let surfaceView {
            embed(surfaceView, in: container)
        }
        context.coordinator.currentTabID = activeTabID
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard activeTabID != context.coordinator.currentTabID else { return }
        context.coordinator.currentTabID = activeTabID

        // Remove old surface view
        for subview in container.subviews {
            subview.removeFromSuperview()
        }

        // Add new surface view
        guard let surfaceView else { return }
        embed(surfaceView, in: container)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func embed(_ surfaceView: SurfaceView, in container: NSView) {
        surfaceView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(surfaceView)
        NSLayoutConstraint.activate([
            surfaceView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            surfaceView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            surfaceView.topAnchor.constraint(equalTo: container.topAnchor),
            surfaceView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    final class Coordinator {
        var currentTabID: UUID?
    }
}
```

Key points:
- Takes `surfaceView` and `activeTabID` as value parameters (not the whole `WindowState`). This is critical: `NSViewRepresentable.updateNSView` is only called when the struct's stored properties change. Passing values forces SwiftUI to track `@Observable` property accesses in the parent view's `body`, ensuring `updateNSView` fires when the active tab changes.
- Uses a plain `NSView` container so we control the SurfaceView lifecycle (not SwiftUI).
- `Coordinator` tracks `currentTabID` to avoid redundant swaps.
- `embed()` uses Auto Layout to fill the container — SurfaceView's `setFrameSize` will fire and update the Metal layer + ghostty surface size.
- Focus transfer is NOT done here — it's handled by `WindowState.requestFocus()` which retries until the view is in the hierarchy.

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Klausemeister/Views/TerminalContentView.swift
git commit -m "Add TerminalContentView NSViewRepresentable for tab swapping"
```

---

### Task 5: Create SidebarView

**Files:**
- Create: `Klausemeister/Views/SidebarView.swift`

- [ ] **Step 1: Write SidebarView**

Create `Klausemeister/Views/SidebarView.swift`:

```swift
import SwiftUI

struct SidebarView: View {
    let windowState: WindowState

    var body: some View {
        VStack(spacing: 0) {
            tabList
            Divider()
            newTabButton
        }
        .frame(width: 220)
    }

    private var tabList: some View {
        List(selection: Binding(
            get: { windowState.activeTabID },
            set: { id in
                if let id { windowState.switchTab(id: id) }
            }
        )) {
            ForEach(windowState.tabs) { tab in
                SidebarTabRow(
                    title: tab.title,
                    isActive: tab.id == windowState.activeTabID,
                    onClose: { windowState.closeTab(id: tab.id) }
                )
                .tag(tab.id)
            }
        }
        .listStyle(.sidebar)
    }

    private var newTabButton: some View {
        Button {
            windowState.createTab()
        } label: {
            Label("New Tab", systemImage: "plus")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

struct SidebarTabRow: View {
    let title: String
    let isActive: Bool
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            Text(title)
                .lineLimit(1)
            Spacer()
            if isHovering {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
```

Key points:
- `List(selection:)` gives us built-in selection highlighting.
- Close button appears on hover via `@State isHovering`.
- "New Tab" button at the bottom with a `+` icon.
- `windowState` is passed directly (not via `@Environment`) — keeps the dependency explicit.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Klausemeister/Views/SidebarView.swift
git commit -m "Add SidebarView with tab list, selection, and close-on-hover"
```

---

### Task 6: Rewrite TerminalContainerView

**Files:**
- Modify: `Klausemeister/TerminalContainerView.swift` (full rewrite)

- [ ] **Step 1: Rewrite TerminalContainerView**

Replace the entire contents of `Klausemeister/TerminalContainerView.swift`:

```swift
import SwiftUI

struct TerminalContainerView: View {
    let windowState: WindowState

    var body: some View {
        HStack(spacing: 0) {
            if windowState.showSidebar {
                SidebarView(windowState: windowState)
                Divider()
            }
            TerminalContentView(
                surfaceView: windowState.activeTab?.surfaceView,
                activeTabID: windowState.activeTabID
            )
        }
        .ignoresSafeArea()
    }
}
```

The old `TerminalRepresentable` struct is deleted — its role is now handled by `TerminalContentView`.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Klausemeister/TerminalContainerView.swift
git commit -m "Rewrite TerminalContainerView with sidebar + terminal content layout"
```

---

### Task 7: Wire up KlausemeisterApp with WindowState and keyboard shortcuts

**Files:**
- Modify: `Klausemeister/KlausemeisterApp.swift` (full rewrite)

- [ ] **Step 1: Rewrite KlausemeisterApp**

Replace the entire contents of `Klausemeister/KlausemeisterApp.swift`:

```swift
import SwiftUI

@main
struct KlausemeisterApp: App {
    @State private var windowState = WindowState()

    var body: some Scene {
        WindowGroup {
            TerminalContainerView(windowState: windowState)
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    windowState.createTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    if let id = windowState.activeTabID {
                        windowState.closeTab(id: id)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Button("Show Previous Tab") {
                    windowState.selectPreviousTab()
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Button("Show Next Tab") {
                    windowState.selectNextTab()
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Divider()

                Button("Toggle Sidebar") {
                    windowState.showSidebar.toggle()
                }
                .keyboardShortcut("\\", modifiers: .command)
            }

            CommandGroup(replacing: .appInfo) {}

            // Cmd+1 through Cmd+9 for tab switching
            CommandMenu("Tabs") {
                ForEach(1...9, id: \.self) { i in
                    Button("Tab \(i)") {
                        windowState.selectTab(at: i)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(i))), modifiers: .command)
                }
            }
        }
    }
}
```

Key points:
- `@State private var windowState` — SwiftUI owns the WindowState lifetime. `WindowState.init()` creates the first tab.
- `.commands` adds keyboard shortcuts to the macOS menu bar. Menu commands intercept before the terminal's `performKeyEquivalent` — this is the standard macOS pattern.
- `CommandGroup(after: .newItem)` places tab actions in the File menu.
- `CommandMenu("Tabs")` creates a separate Tabs menu for Cmd+1-9.
- Window width increased from 800 to 900 to accommodate the 220pt sidebar.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Klausemeister/KlausemeisterApp.swift
git commit -m "Wire up WindowState and keyboard shortcuts in KlausemeisterApp"
```

---

### Task 8: Manual Verification

This task has no code changes. Run the app and verify all acceptance criteria from the spec.

- [ ] **Step 1: Build and run**

```bash
xcodebuild -project Klausemeister.xcodeproj -scheme Klausemeister -configuration Debug build
open build/Debug/Klausemeister.app
```

Or open in Xcode and press Cmd+R.

- [ ] **Step 2: Verify acceptance criteria**

1. App launches with one tab in sidebar, terminal fills content area
2. `Cmd+T` creates a new tab, sidebar updates, new terminal gets focus — type to confirm keyboard input works
3. Click a sidebar entry — terminal switches, type to confirm keyboard input works immediately
4. `Cmd+W` closes the active tab, focus transfers to adjacent tab
5. Close the last tab — a fresh one is created (never empty state)
6. `Cmd+\` toggles the sidebar
7. `Cmd+1` through `Cmd+9` switches to tab by position
8. `Cmd+Shift+[` / `Cmd+Shift+]` cycles through tabs

- [ ] **Step 3: Fix any issues found during verification**

If any criterion fails, debug and fix before marking this task complete.

- [ ] **Step 4: Final commit (if fixes were needed)**

```bash
git add -A
git commit -m "Fix issues found during manual verification of sidebar tabs"
```
