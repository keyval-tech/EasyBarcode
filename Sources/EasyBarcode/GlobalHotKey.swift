import AppKit
import Carbon.HIToolbox

enum HotKeySlot: String {
    case main
    case history

    var defaultsKeyCode: String {
        self == .main ? "hotKeyKeyCode" : "historyHotKeyKeyCode"
    }

    var defaultsModifiers: String {
        self == .main ? "hotKeyModifiers" : "historyHotKeyModifiers"
    }

    var defaultConfig: HotKeyConfig {
        self == .main ? .default : .historyDefault
    }
}

struct HotKeyConfig: Equatable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags

    static let `default` = HotKeyConfig(keyCode: 11, modifiers: [.option])
    static let historyDefault = HotKeyConfig(keyCode: 4, modifiers: [.option])

    static func load(for slot: HotKeySlot) -> HotKeyConfig {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: slot.defaultsKeyCode) != nil else {
            return slot.defaultConfig
        }

        let code = UInt32(defaults.integer(forKey: slot.defaultsKeyCode))
        let raw = UInt(defaults.integer(forKey: slot.defaultsModifiers))
        let modifiers = NSEvent.ModifierFlags(rawValue: raw)
        guard !modifiers.intersection([.command, .option, .control]).isEmpty else {
            return slot.defaultConfig
        }
        return HotKeyConfig(keyCode: code, modifiers: modifiers)
    }

    func save(for slot: HotKeySlot) {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: slot.defaultsKeyCode)
        defaults.set(Int(modifiers.rawValue), forKey: slot.defaultsModifiers)
    }

    var displayString: String {
        modifierGlyphs + keyLabel
    }

    var modifierGlyphs: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result
    }

    var keyLabel: String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "↩"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "⇥"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "⌫"
        case 53: return "esc"
        default: return "Key\(keyCode)"
        }
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}

enum EasyBarcodeHotKeyID {
    static let main: UInt32 = 1
    static let history: UInt32 = 2
}

private let easyBarcodeHotKeySignature: OSType = 0x4542484B // 'EBHK'

private func easyBarcodeHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return noErr }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return noErr }

    DispatchQueue.main.async {
        GlobalHotKey.shared.fire(id: hotKeyID.id)
    }
    return noErr
}

final class GlobalHotKey {
    struct Registration {
        let config: HotKeyConfig
        let handler: () -> Void
    }

    static let shared = GlobalHotKey()

    private var registrations: [UInt32: Registration] = [:]
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?

    private init() {}

    @discardableResult
    func register(_ config: HotKeyConfig, id: UInt32, handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()

        let previous = registrations[id]
        if let previousRef = hotKeyRefs.removeValue(forKey: id) {
            UnregisterEventHotKey(previousRef)
        }

        if let ref = makeHotKeyRef(config, id: id) {
            hotKeyRefs[id] = ref
            registrations[id] = Registration(config: config, handler: handler)
            return true
        }

        // Restore the previous binding if the new shortcut is unavailable.
        if let previous, let ref = makeHotKeyRef(previous.config, id: id) {
            hotKeyRefs[id] = ref
            registrations[id] = previous
        }
        return false
    }

    func config(for id: UInt32) -> HotKeyConfig? {
        registrations[id]?.config
    }

    fileprivate func fire(id: UInt32) {
        registrations[id]?.handler()
    }

    private func makeHotKeyRef(_ config: HotKeyConfig, id: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: easyBarcodeHotKeySignature, id: id)
        let status = RegisterEventHotKey(
            config.keyCode,
            config.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr else { return nil }
        return ref
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            easyBarcodeHotKeyHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )
    }
}
