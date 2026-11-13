import AppKit

/// A standard titled window that also handles the shortcut keys we need even
/// though this is an agent (menu-bar-only) app without a visible main menu.
final class BarcodeWindow: NSWindow {
    /// Called for Tab / Shift-Tab when the field editor does not own the key.
    var onTabKey: ((_ backwards: Bool) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48, !(firstResponder is NSTextView) {
            onTabKey?(event.modifierFlags.contains(.shift))
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w":
            performClose(nil)
            return true
        case "m":
            performMiniaturize(nil)
            return true
        case "v":
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            return true
        case "c":
            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            return true
        case "x":
            NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            return true
        case "a":
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}
