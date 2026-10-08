import Foundation

/// Dubeolsik (두벌식) Hangul composition for the NaturalKana keyboard.
/// Keys are compatibility jamo (ㄱ, ㅏ…). Only the syllable block being typed is editable; everything before it
/// is ordinary text. Each call returns how many characters before the cursor to delete and what to insert.
public struct HangulComposer: Equatable, Sendable {
    public struct Edit: Equatable, Sendable {
        public let delete: Int
        public let insert: String
        public init(delete: Int, insert: String) { self.delete = delete; self.insert = insert }
    }

    static let initials: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    static let medials: [Character] = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    /// Index 0 is "no final consonant". ㄸ, ㅃ and ㅉ never end a syllable.
    static let finals: [Character?] = [nil] + Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ").map { $0 }
    static let compoundVowels: [String: Character] = ["ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ", "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅡㅣ": "ㅢ"]
    static let compoundFinals: [String: Character] = ["ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ",
                                                      "ㄹㅅ": "ㄽ", "ㄹㅌ": "ㄾ", "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ"]

    public static func isConsonant(_ key: Character) -> Bool { initials.contains(key) }
    public static func isVowel(_ key: Character) -> Bool { medials.contains(key) }
    public static func isJamo(_ key: Character) -> Bool { isConsonant(key) || isVowel(key) }

    /// The syllable block being typed.
    private struct Block: Equatable, Sendable {
        var initial: Character?
        var medial: Character?
        var final: Character?
        /// Keys typed for this block, so backspace removes one key at a time (ㅘ → ㅗ, ㄺ → ㄹ).
        var keys: [Character] = []
        var isEmpty: Bool { keys.isEmpty }
        var text: String {
            guard let medial else { return initial.map(String.init) ?? "" }
            guard let initial, let l = HangulComposer.initials.firstIndex(of: initial),
                  let v = HangulComposer.medials.firstIndex(of: medial),
                  let t = HangulComposer.finals.firstIndex(of: final) else { return String(medial) }
            return String(Character(Unicode.Scalar(0xAC00 + (l * 21 + v) * 28 + t)!))
        }
    }
    private var block = Block()

    public init() {}
    /// True while a block is being typed; its text is the last character before the cursor.
    public var isComposing: Bool { !block.isEmpty }
    /// The block's text as shown before the cursor.
    public var composingText: String { block.text }

    /// Ends the current block, e.g. when the cursor moves or another key is pressed. Its text stays as typed.
    public mutating func reset() { block = Block() }

    public mutating func input(_ key: Character) -> Edit {
        let before = block.text
        guard !Self.apply(key, to: &block) else { return Edit(delete: before.isEmpty ? 0 : 1, insert: block.text) }
        // The key starts a new block. A vowel takes the previous final consonant with it (한 + ㅏ → 하나, 닭 + ㅏ → 달가).
        var next = Block()
        if Self.isVowel(key), block.medial != nil, let final = block.final {
            let split = Self.split(final)
            block.final = split.keep
            block.keys.removeLast()
            next.initial = split.move
            next.keys = [split.move]
        }
        let committed = block.text
        block = next
        _ = Self.apply(key, to: &block)
        return Edit(delete: before.isEmpty ? 0 : 1, insert: committed + block.text)
    }

    /// Removes the last key of the block; nil when nothing is being composed (an ordinary backspace).
    public mutating func deleteBackward() -> Edit? {
        guard !block.isEmpty else { return nil }
        let keys = block.keys.dropLast()
        block = Block()
        for key in keys { _ = Self.apply(key, to: &block) }
        return Edit(delete: 1, insert: block.text)
    }

    /// Adds `key` to `block` if it belongs to the same syllable; false when it must start a new block.
    private static func apply(_ key: Character, to block: inout Block) -> Bool {
        if isConsonant(key) {
            switch (block.initial, block.medial, block.final) {
            case (nil, nil, _): block.initial = key
            case (_?, _?, nil) where finals.contains(key): block.final = key
            case (_?, _?, let final?):
                guard let compound = compoundFinals[String([final, key])] else { return false }
                block.final = compound
            default: return false
            }
        } else if isVowel(key) {
            switch (block.medial, block.final) {
            case (nil, nil): block.medial = key
            case (let medial?, nil):
                guard let compound = compoundVowels[String([medial, key])] else { return false }
                block.medial = compound
            default: return false
            }
        } else { return false }
        block.keys.append(key)
        return true
    }

    /// For a final consonant moving to the next syllable: what stays (ㄺ keeps ㄹ) and what moves (ㄱ).
    /// Compound finals are always typed as two keys, so the moved part is the block's last key.
    private static func split(_ final: Character) -> (keep: Character?, move: Character) {
        if let pair = compoundFinals.first(where: { $0.value == final })?.key { return (pair.first, pair.last!) }
        return (nil, final)
    }
}
