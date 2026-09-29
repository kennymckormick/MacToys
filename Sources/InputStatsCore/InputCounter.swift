import Foundation

/// Counts inserted grapheme clusters, never net document length.
/// Focus changes, paste and programmatic replacements are filtered by the caller.
public final class InputCounter {
    private var lastString: String?
    private var lastCharacters: [Character] = []

    public struct Delta: Equatable {
        public var keyboardChars = 0
        public var keyboardWords = 0
        public var voiceChars = 0
        public var voiceWords = 0
        public init() {}
        public var isZero: Bool { keyboardChars == 0 && keyboardWords == 0 && voiceChars == 0 && voiceWords == 0 }
    }

    public init() {}

    public func reset(to content: String?) {
        lastString = content
        lastCharacters = content.map(Array.init) ?? []
    }

    /// Uncommitted IME snapshots do not replace the committed baseline.
    public func step(content: String, dictating: Bool, provisional: Bool = false) -> Delta {
        var delta = Delta()
        guard !provisional, content != lastString else { return delta }
        guard lastString != nil else { reset(to: content); return delta }
        let old = lastCharacters
        let new = Array(content)
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        lastString = content
        lastCharacters = new
        let inserted = Array(new[prefix..<(new.count - suffix)])
        guard !inserted.isEmpty else { return delta }
        // Extending an existing Latin word must not count that word a second time.
        let left: [Character] = prefix > 0 ? [new[prefix - 1]] : []
        let right: [Character] = suffix > 0 ? [new[new.count - suffix]] : []
        let words = max(0, TextCount.words(left + inserted + right) - TextCount.words(left + right))
        if dictating { delta.voiceChars = inserted.count; delta.voiceWords = words }
        else { delta.keyboardChars = inserted.count; delta.keyboardWords = words }
        return delta
    }
}
