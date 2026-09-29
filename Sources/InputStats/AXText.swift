import ApplicationServices
import Cocoa

/// Bounded AX reads. Secure text is rejected before requesting its value.
enum AXText {
    static let maximumUTF16Length = 65_536
    static let system = AXUIElementCreateSystemWide()
    struct Snapshot {
        var element: AXUIElement?
        var content: String?
        var blocked = false
        var secure = false
        var tooLarge = false
        var selected: String?
    }
    static func configure() { AXUIElementSetMessagingTimeout(system, 0.12) }
    static func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
    static func read(_ element: AXUIElement?, secureInput: Bool, forceFallback: Bool = false) -> Snapshot {
        guard let element else { return Snapshot(blocked: true) }
        if secureInput || string(element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole {
            return Snapshot(element: element, blocked: true, secure: true)
        }
        if forceFallback { return Snapshot(element: element) }
        var writable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &writable)
        let role = string(element, kAXRoleAttribute) ?? ""
        guard writable.boolValue || role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole else {
            return Snapshot(element: element, blocked: true)
        }
        var length: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &length) == .success,
           let count = length as? NSNumber, count.intValue > maximumUTF16Length {
            return Snapshot(element: element, tooLarge: true)
        }
        guard let value = string(element, kAXValueAttribute) else { return Snapshot(element: element) }
        guard value.utf16.count <= maximumUTF16Length else {
            return Snapshot(element: element, tooLarge: true)
        }
        return Snapshot(element: element, content: value, selected: string(element, kAXSelectedTextAttribute))
    }
}
