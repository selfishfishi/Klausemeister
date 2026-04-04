# Sidebar with Multiple Terminal Tabs

**Linear issue:** KLA-7
**Date:** 2026-04-04

## Context

Klausemeister currently renders a single terminal filling the entire window. This spec adds the ability to create, switch, and close multiple terminal sessions via a sidebar. This is foundational — every future feature (worktrees, specs, diffs) attaches to tabs.

## Data Model

### TabSession (`@Observable`, `@MainActor`, new file)

```
- id: UUID
- title: String (defaults to "Terminal")
- surfaceView: SurfaceView (owns the ghostty surface)
```

Title is static "Terminal" for now. Dynamic title propagation from the terminal title callback is a follow-up within this ticket's scope.

### WindowState (`@Observable`, `@MainActor`, new file)

```
- tabs: [TabSession]
- activeTabID: UUID?
- activeTab: TabSession? (computed — lookup by UUID)
- showSidebar: Bool (default true)
```

### Tab Operations

**createTab():**
1. Create new `SurfaceView(frame: .zero)`
2. Call `initializeSurface(app:workingDirectory:)` on it
3. Wrap in `TabSession`, append to `tabs`
4. Set as `activeTabID`
5. Update `GhosttyApp.shared.currentSurface`

**closeTab(id:):**
1. Find tab by ID, remove from `tabs` array
2. ARC + `SurfaceView.deinit` handles `ghostty_surface_free` — no explicit free to avoid double-free
3. If it was the active tab, switch to adjacent (prefer next, fall back to previous)
4. If no tabs remain, create a fresh one (never empty state)

**switchTab(id:):**
1. `ghostty_surface_set_focus(surface, false)` on old tab's surface
2. Set `activeTabID` to new tab
3. Update `GhosttyApp.shared.currentSurface` to new tab's surface
4. View layer swaps the SurfaceView (triggers focus transfer protocol)

## UI Layout

```
+--------------------------------------------------+
| Toolbar (macOS native)                           |
+----------+---------------------------------------+
| Sidebar  | Terminal Content                      |
| (220pt)  |                                       |
|          |                                       |
| [+ New]  |    Active tab's SurfaceView           |
|          |    (fills remaining space)             |
| Tab 1  * |                                       |
| Tab 2    |                                       |
| Tab 3    |                                       |
|          |                                       |
+----------+---------------------------------------+
```

### SidebarView (SwiftUI, new file)

- Vertical `List` of tab entries
- Each entry: SF Symbol `terminal`, title, close button on hover
- Active tab highlighted with accent color
- "+" button at bottom to create new tab
- Click to call `windowState.switchTab(id:)`

### TerminalContentView (NSViewRepresentable, new file)

- Wraps the active tab's `SurfaceView`
- Swaps the underlying NSView when `activeTabID` changes
- On swap: remove old SurfaceView from superview, add new one, trigger focus transfer

### TerminalContainerView (modified)

- Changes from single `TerminalRepresentable` to `HStack` with sidebar + content area
- Sidebar toggleable via `Cmd+\`

### KlausemeisterApp (modified)

- Creates `WindowState` as `@State`, passes into the view hierarchy
- `WindowState.init` creates the first tab automatically

### SurfaceView (modified)

- Remove auto-focus from `viewDidMoveToWindow()` — focus transfer protocol is the sole owner of first responder management
- Keep `becomeFirstResponder()` / `resignFirstResponder()` focus callbacks as-is

## Focus Transfer Protocol

When switching tabs:

1. `ghostty_surface_set_focus(surface, false)` on old tab's surface
2. Update `activeTabID` on `WindowState`
3. Update `GhosttyApp.shared.currentSurface` to new tab's surface
4. `TerminalContentView` swaps the NSView in its hierarchy
5. `DispatchQueue.main.async` -> `window.makeFirstResponder(newSurfaceView)`
6. `SurfaceView.becomeFirstResponder()` automatically calls `ghostty_surface_set_focus(surface, true)` — no explicit call needed
7. If `makeFirstResponder` fails (view not yet in hierarchy), retry at 10ms intervals up to 500ms

## Keyboard Shortcuts

Handled via invisible SwiftUI `Button` views with `.keyboardShortcut` modifiers in `TerminalContainerView`. These are intercepted by the SwiftUI responder chain before reaching the terminal's `performKeyEquivalent`:

| Shortcut | Action |
| --- | --- |
| `Cmd+T` | New tab |
| `Cmd+W` | Close active tab |
| `Cmd+Shift+[` | Previous tab |
| `Cmd+Shift+]` | Next tab |
| `Cmd+1` through `Cmd+9` | Switch to tab by position |
| `Cmd+\` | Toggle sidebar |

## Files to Create/Modify

| Action | File | Purpose |
| --- | --- | --- |
| Create | `Klausemeister/Session/TabSession.swift` | Tab data model |
| Create | `Klausemeister/Session/WindowState.swift` | Window state with tab list and operations |
| Create | `Klausemeister/Views/SidebarView.swift` | Sidebar tab list UI |
| Create | `Klausemeister/Views/TerminalContentView.swift` | Active tab's terminal display (NSViewRepresentable) |
| Modify | `Klausemeister/TerminalContainerView.swift` | HStack with sidebar + content |
| Modify | `Klausemeister/KlausemeisterApp.swift` | Initialize WindowState |
| Modify | `Klausemeister/Terminal/SurfaceView.swift` | Remove auto-focus from viewDidMoveToWindow |

## Error Handling

Minimal — all in-process:
- `ghostty_surface_new` returns nil: don't add the tab
- Last tab closed: auto-create a fresh one
- Focus retry exhausted after 500ms: surface still works, user can click to focus

## Deferred

- Tab groups with colors
- Drag-to-reorder
- Split panes within tabs
- Tab content types beyond terminal
- Session persistence/restore
- Activity status indicators

## Verification

1. App launches with one tab in sidebar, terminal fills content area
2. `Cmd+T` creates a new tab, sidebar updates, new terminal gets focus
3. Clicking a sidebar entry switches the terminal, keyboard input works immediately
4. `Cmd+W` closes the active tab, focus transfers to adjacent tab
5. Closing the last tab creates a fresh one (never empty state)
6. Sidebar toggles with `Cmd+\`
7. `Cmd+1-9` switches to tab by position
8. `Cmd+Shift+[` / `]` cycles through tabs
