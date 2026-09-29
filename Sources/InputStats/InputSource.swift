import Carbon

/// 检测当前键盘输入法是否为 CJK（中/日/韩），用于按键兜底时的字数估算。
enum InputSource {
    static func isCJK() -> Bool {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return false }
        guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages) else { return false }
        let langs = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as? [String] ?? []
        guard let first = langs.first else { return false }
        return first.hasPrefix("zh") || first.hasPrefix("ja") || first.hasPrefix("ko")
    }
}
