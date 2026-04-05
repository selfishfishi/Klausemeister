import AppKit
import GhosttyKit
import QuartzCore

// swiftlint:disable type_body_length
/// NSView that hosts a ghostty terminal surface with proper keyboard handling.
/// Follows the Calyx/Ghostty pattern: CAMetalLayer backing, raw keycode input,
/// interpretKeyEvents for IME, and explicit first responder management.
final class SurfaceView: NSView, NSTextInputClient, CALayerDelegate {
    private(set) var surface: ghostty_surface_t?
    private var focused = false
    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?
    private var currentCursor: NSCursor = .iBeam
    private var isCursorVisible = true

    let metalLayer: CAMetalLayer

    // MARK: - Initialization

    override init(frame: NSRect) {
        // swiftlint:disable:next identifier_name
        let ml = CAMetalLayer()
        ml.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        ml.pixelFormat = .bgra8Unorm
        ml.framebufferOnly = true
        ml.isOpaque = true
        ml.displaySyncEnabled = true
        metalLayer = ml
        super.init(frame: frame)
        wantsLayer = true
        layer = ml
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func initializeSurface(app: ghostty_app_t, workingDirectory: String? = nil) {
        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform.macos = ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        )
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.backend = GHOSTTY_SURFACE_IO_BACKEND_EXEC
        config.scale_factor = Double(metalLayer.contentsScale)

        // swiftlint:disable:next identifier_name
        if let wd = workingDirectory {
            wd.withCString { ptr in
                config.working_directory = ptr
                self.surface = ghostty_surface_new(app, &config)
            }
        } else {
            surface = ghostty_surface_new(app, &config)
        }

        guard surface != nil else { return }

        let backingSize = convertToBacking(bounds).size
        ghostty_surface_set_content_scale(
            surface,
            Double(metalLayer.contentsScale),
            Double(metalLayer.contentsScale)
        )
        ghostty_surface_set_size(
            surface,
            UInt32(backingSize.width),
            UInt32(backingSize.height)
        )
    }

    // MARK: - View Lifecycle

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { setFocus(true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { setFocus(false) }
        return result
    }

    // swiftlint:disable:next unneeded_override
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil, !isCursorVisible {
            NSCursor.unhide()
            isCursorVisible = true
        }
    }

    private func setFocus(_ focused: Bool) {
        self.focused = focused
        guard let surface else { return }
        ghostty_surface_set_focus(surface, focused)
    }

    // MARK: - Cursor Management

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [
                .activeAlways,
                .cursorUpdate,
                .mouseMoved,
                .mouseEnteredAndExited,
                .inVisibleRect
            ],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with _: NSEvent) {
        currentCursor.set()
    }

    func applyCursorShape(_ shape: ghostty_action_mouse_shape_e) {
        currentCursor = MouseCursorMapping.nsCursor(for: shape)
        currentCursor.set()
    }

    func applyCursorVisibility(_ visibility: ghostty_action_mouse_visibility_e) {
        let visible = (visibility == GHOSTTY_MOUSE_VISIBLE)
        guard visible != isCursorVisible else { return }
        isCursorVisible = visible
        if visible {
            NSCursor.unhide()
        } else {
            NSCursor.hide()
        }
    }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let backingSize = convertToBacking(NSRect(origin: .zero, size: newSize)).size
        metalLayer.drawableSize = backingSize
        guard let surface else { return }
        ghostty_surface_set_size(surface, UInt32(backingSize.width), UInt32(backingSize.height))
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let screen = window?.screen ?? NSScreen.main else { return }
        let scale = screen.backingScaleFactor
        metalLayer.contentsScale = scale
        guard let surface else { return }
        ghostty_surface_set_content_scale(surface, Double(scale), Double(scale))
        let backingSize = convertToBacking(bounds).size
        metalLayer.drawableSize = backingSize
        ghostty_surface_set_size(surface, UInt32(backingSize.width), UInt32(backingSize.height))
    }

    // MARK: - Keyboard Input (following Calyx's pattern)

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            interpretKeyEvents([event])
            return
        }

        // Get translation mods from ghostty for option-as-alt handling
        let mods = KeyMapping.translateModifiers(event.modifierFlags)
        let translationMods = ghostty_surface_key_translation_mods(surface, mods)
        let translationFlags = KeyMapping.modifierFlags(from: translationMods)

        // Build translation event with adjusted modifiers
        let translationEvent: NSEvent
        if translationFlags == event.modifierFlags.intersection(
            [.shift, .control, .option, .command, .capsLock, .numericPad]
        ) {
            translationEvent = event
        } else {
            var adjustedFlags = event.modifierFlags
            for flag: NSEvent.ModifierFlags in [.shift, .control, .option, .command] {
                if translationFlags.contains(flag) {
                    adjustedFlags.insert(flag)
                } else {
                    adjustedFlags.remove(flag)
                }
            }
            translationEvent = NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: adjustedFlags,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: adjustedFlags) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) ?? event
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        // Set up text accumulator for IME
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        let hadMarkedText = markedText.length > 0

        // Route through the input system (IME, dead keys, etc.)
        interpretKeyEvents([translationEvent])

        // Sync preedit state
        if markedText.length == 0, hadMarkedText {
            var key = ghostty_input_key_s()
            key.action = action
            key.composing = true
            key.text = nil
            ghostty_surface_key(surface, key)
        }

        if let texts = keyTextAccumulator, !texts.isEmpty {
            for text in texts {
                sendKey(action: action, event: event, translationEvent: translationEvent, text: text)
            }
        } else {
            let text = KeyMapping.ghosttyCharacters(from: translationEvent)
            sendKey(
                action: action,
                event: event,
                translationEvent: translationEvent,
                text: text,
                composing: markedText.length > 0 || hadMarkedText
            )
        }
    }

    override func keyUp(with event: NSEvent) {
        sendKey(action: GHOSTTY_ACTION_RELEASE, event: event)
    }

    override func flagsChanged(with event: NSEvent) {
        if hasMarkedText() { return }

        let mods = KeyMapping.translateModifiers(event.modifierFlags)
        let keyMod: UInt32
        switch event.keyCode {
        case 0x39: keyMod = GHOSTTY_MODS_CAPS.rawValue // CapsLock
        case 0x38, 0x3C: keyMod = GHOSTTY_MODS_SHIFT.rawValue // Shift L/R
        case 0x3B, 0x3E: keyMod = GHOSTTY_MODS_CTRL.rawValue // Control L/R
        case 0x3A, 0x3D: keyMod = GHOSTTY_MODS_ALT.rawValue // Option L/R
        case 0x37, 0x36: keyMod = GHOSTTY_MODS_SUPER.rawValue // Command L/R
        default: return
        }

        let action: ghostty_input_action_e = (mods.rawValue & keyMod != 0)
            ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        sendKey(action: action, event: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, focused, let surface else { return false }

        var ghosttyEvent = KeyMapping.translateKeyEvent(event, action: GHOSTTY_ACTION_PRESS)
        let chars = event.characters ?? ""
        let isBinding = chars.withCString { ptr -> Bool in
            ghosttyEvent.text = ptr
            return ghostty_surface_key_is_binding(surface, ghosttyEvent, nil)
        }
        if isBinding {
            keyDown(with: event)
            return true
        }
        return false
    }

    @discardableResult
    private func sendKey(
        action: ghostty_input_action_e,
        event: NSEvent,
        translationEvent: NSEvent? = nil,
        text: String? = nil,
        composing: Bool = false
    ) -> Bool {
        guard let surface else { return false }

        var key = KeyMapping.translateKeyEvent(
            event,
            action: action,
            translationMods: translationEvent?.modifierFlags
        )
        key.composing = composing

        if let text, !text.isEmpty {
            return text.withCString { ptr in
                key.text = ptr
                return ghostty_surface_key(surface, key)
            }
        } else {
            return ghostty_surface_key(surface, key)
        }
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendMouse(event: event, button: GHOSTTY_MOUSE_LEFT, state: GHOSTTY_MOUSE_PRESS)
    }

    override func mouseUp(with event: NSEvent) {
        sendMouse(event: event, button: GHOSTTY_MOUSE_LEFT, state: GHOSTTY_MOUSE_RELEASE)
    }

    override func mouseDragged(with event: NSEvent) {
        sendMousePos(event: event)
    }

    override func mouseMoved(with event: NSEvent) {
        sendMousePos(event: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        sendMouse(event: event, button: GHOSTTY_MOUSE_RIGHT, state: GHOSTTY_MOUSE_PRESS)
    }

    override func rightMouseUp(with event: NSEvent) {
        sendMouse(event: event, button: GHOSTTY_MOUSE_RIGHT, state: GHOSTTY_MOUSE_RELEASE)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_scroll(
            surface,
            event.scrollingDeltaX,
            event.scrollingDeltaY,
            0 // scroll mods (packed int, 0 = none)
        )
    }

    private func sendMouse(
        event: NSEvent,
        button: ghostty_input_mouse_button_e,
        state: ghostty_input_mouse_state_e
    ) {
        guard let surface else { return }
        let mods = KeyMapping.translateModifiers(event.modifierFlags)
        ghostty_surface_mouse_button(surface, state, button, mods)
    }

    override func mouseEntered(with event: NSEvent) {
        sendMousePos(event: event)
    }

    override func mouseExited(with event: NSEvent) {
        guard let surface else { return }
        let mods = KeyMapping.translateModifiers(event.modifierFlags)
        ghostty_surface_mouse_pos(surface, -1, -1, mods)
    }

    private func sendMousePos(event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        let mods = KeyMapping.translateModifiers(event.modifierFlags)
        ghostty_surface_mouse_pos(surface, pos.x, bounds.height - pos.y, mods)
    }

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange _: NSRange) {
        let str: String
        // swiftlint:disable identifier_name
        if let s = string as? String {
            str = s
        } else if let s = string as? NSAttributedString {
            str = s.string
        } else {
            return
        }
        // swiftlint:enable identifier_name
        markedText = NSMutableAttributedString()
        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(str)
        } else if let surface {
            str.withCString { ptr in
                var key = ghostty_input_key_s()
                key.action = GHOSTTY_ACTION_PRESS
                key.text = ptr
                ghostty_surface_key(surface, key)
            }
        }
    }

    func setMarkedText(_ string: Any, selectedRange _: NSRange, replacementRange _: NSRange) {
        // swiftlint:disable identifier_name
        if let s = string as? NSAttributedString {
            markedText = NSMutableAttributedString(attributedString: s)
        } else if let s = string as? String {
            markedText = NSMutableAttributedString(string: s)
        }
        // swiftlint:enable identifier_name
    }

    func unmarkText() {
        markedText = NSMutableAttributedString()
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        if markedText.length > 0 {
            return NSRange(location: 0, length: markedText.length)
        }
        return NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func attributedSubstring(forProposedRange _: NSRange, actualRange _: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func validAttributedString(for proposedString: NSAttributedString, range _: NSRange) -> NSAttributedString? {
        proposedString
    }

    func firstRect(forCharacterRange _: NSRange, actualRange _: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        let viewRect = NSRect(x: 0, y: bounds.height - 20, width: 200, height: 20)
        let windowRect = convert(viewRect, to: nil)
        return window.convertToScreen(windowRect)
    }

    func characterIndex(for _: NSPoint) -> Int {
        0
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    /// Silence NSBeep for unhandled key commands
    override func doCommand(by _: Selector) {}

    // MARK: - Cleanup

    deinit {
        if !isCursorVisible {
            NSCursor.unhide()
        }
        if let surface {
            ghostty_surface_free(surface)
        }
    }
}

// swiftlint:enable type_body_length
