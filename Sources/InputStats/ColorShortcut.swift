import AppKit
import Carbon

struct ColorShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    static let standard = ColorShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey | cmdKey))
    static let letters: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0", 31: "O", 32: "U", 34: "I", 35: "P",
        37: "L", 38: "J", 40: "K", 45: "N", 46: "M"
    ]
    var isValid: Bool {
        Self.letters[keyCode] != nil && modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 &&
            modifiers & ~UInt32(controlKey | optionKey | cmdKey | shiftKey) == 0
    }
    var label: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + (Self.letters[keyCode] ?? "?")
    }
    init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    init?(event: NSEvent) {
        var mask: UInt32 = 0
        for (flag, carbon): (NSEvent.ModifierFlags, Int) in [(.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)] {
            if event.modifierFlags.contains(flag) { mask |= UInt32(carbon) }
        }
        self.init(keyCode: UInt32(event.keyCode), modifiers: mask)
        if !isValid { return nil }
    }
}

/// Carbon registers one shortcut with the OS; there is no global key monitor or polling.
final class ColorShortcutRegistration {
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var current: ColorShortcut?
    var action: (() -> Void)?
    private static let signature: OSType = 0x4D544350 // MTCP

    func register(_ shortcut: ColorShortcut) -> OSStatus {
        if current == shortcut, hotKey != nil { return noErr }
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr, identifier.signature == ColorShortcutRegistration.signature, identifier.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }
                let owner = Unmanaged<ColorShortcutRegistration>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { [weak owner] in owner?.action?() }
                return noErr
            }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return status }
        }
        var candidate: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: Self.signature, id: 1), GetApplicationEventTarget(), 0, &candidate)
        if status == noErr {
            unregister()
            hotKey = candidate; current = shortcut
        }
        return status
    }
    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil; current = nil
    }
    deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }
}
