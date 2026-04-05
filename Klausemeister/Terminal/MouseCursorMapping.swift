import AppKit
import GhosttyKit

/// Translates ghostty mouse shape actions to NSCursor instances.
/// Mirrors the KeyMapping pattern: caseless enum namespace with pure static functions.
enum MouseCursorMapping {
    static func nsCursor(for shape: ghostty_action_mouse_shape_e) -> NSCursor {
        switch shape {
        case GHOSTTY_MOUSE_SHAPE_DEFAULT,
             GHOSTTY_MOUSE_SHAPE_HELP,
             GHOSTTY_MOUSE_SHAPE_PROGRESS,
             GHOSTTY_MOUSE_SHAPE_WAIT:
            .arrow
        case GHOSTTY_MOUSE_SHAPE_CONTEXT_MENU:
            .contextualMenu
        case GHOSTTY_MOUSE_SHAPE_POINTER:
            .pointingHand
        case GHOSTTY_MOUSE_SHAPE_CELL,
             GHOSTTY_MOUSE_SHAPE_CROSSHAIR:
            .crosshair
        case GHOSTTY_MOUSE_SHAPE_TEXT:
            .iBeam
        case GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT:
            .iBeamCursorForVerticalLayout
        case GHOSTTY_MOUSE_SHAPE_ALIAS:
            .dragLink
        case GHOSTTY_MOUSE_SHAPE_COPY:
            .dragCopy
        case GHOSTTY_MOUSE_SHAPE_MOVE,
             GHOSTTY_MOUSE_SHAPE_GRAB,
             GHOSTTY_MOUSE_SHAPE_ALL_SCROLL:
            .openHand
        case GHOSTTY_MOUSE_SHAPE_GRABBING:
            .closedHand
        case GHOSTTY_MOUSE_SHAPE_NO_DROP,
             GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED:
            .operationNotAllowed
        case GHOSTTY_MOUSE_SHAPE_COL_RESIZE,
             GHOSTTY_MOUSE_SHAPE_EW_RESIZE:
            .resizeLeftRight
        case GHOSTTY_MOUSE_SHAPE_ROW_RESIZE,
             GHOSTTY_MOUSE_SHAPE_NS_RESIZE:
            .resizeUpDown
        case GHOSTTY_MOUSE_SHAPE_N_RESIZE:
            .resizeUp
        case GHOSTTY_MOUSE_SHAPE_E_RESIZE:
            .resizeRight
        case GHOSTTY_MOUSE_SHAPE_S_RESIZE:
            .resizeDown
        case GHOSTTY_MOUSE_SHAPE_W_RESIZE:
            .resizeLeft
        case GHOSTTY_MOUSE_SHAPE_NE_RESIZE:
            privateCursor("_windowResizeNorthEastCursor") ?? .arrow
        case GHOSTTY_MOUSE_SHAPE_NW_RESIZE:
            privateCursor("_windowResizeNorthWestCursor") ?? .arrow
        case GHOSTTY_MOUSE_SHAPE_SE_RESIZE:
            privateCursor("_windowResizeSouthEastCursor") ?? .arrow
        case GHOSTTY_MOUSE_SHAPE_SW_RESIZE:
            privateCursor("_windowResizeSouthWestCursor") ?? .arrow
        case GHOSTTY_MOUSE_SHAPE_NESW_RESIZE:
            privateCursor("_windowResizeNorthEastSouthWestCursor") ?? .resizeLeftRight
        case GHOSTTY_MOUSE_SHAPE_NWSE_RESIZE:
            privateCursor("_windowResizeNorthWestSouthEastCursor") ?? .resizeUpDown
        case GHOSTTY_MOUSE_SHAPE_ZOOM_IN:
            privateCursor("_zoomInCursor") ?? .crosshair
        case GHOSTTY_MOUSE_SHAPE_ZOOM_OUT:
            privateCursor("_zoomOutCursor") ?? .crosshair
        default:
            .arrow
        }
    }

    /// Looks up undocumented NSCursor class methods for cursors not exposed in the public API.
    /// Returns nil if the selector is unavailable (e.g., removed in a future macOS version).
    private static func privateCursor(_ name: String) -> NSCursor? {
        NSCursor.perform(Selector(name))?.takeUnretainedValue() as? NSCursor
    }
}
