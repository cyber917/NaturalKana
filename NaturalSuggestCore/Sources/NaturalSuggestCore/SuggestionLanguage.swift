import Foundation
import NaturalLanguage

/// A suggestion language, identified by its language pack folder (Resources/Languages/<rawValue>).
/// Saved settings store the raw value, as the earlier enum did ("japanese", "english", "chinese").
public struct SuggestionLanguage: RawRepresentable, Hashable, Codable, CaseIterable, Sendable {
    public let rawValue: String
    /// Nil for a language without a bundled pack (for example one saved by a newer release).
    public init?(rawValue: String) {
        guard LanguagePack.byID[rawValue] != nil else { return nil }
        self.rawValue = rawValue
    }
    private init(known: String) { rawValue = known }
    public static let japanese = SuggestionLanguage(known: "japanese")
    public static let english = SuggestionLanguage(known: "english")
    public static let chinese = SuggestionLanguage(known: "chinese")
    public static var allCases: [SuggestionLanguage] { LanguagePack.bundled.map { SuggestionLanguage(known: $0.id) } }

    public var pack: LanguagePack {
        guard let pack = LanguagePack.byID[rawValue] else { preconditionFailure("No language pack for \(rawValue)") }
        return pack
    }

    /// Languages offered in settings. On Mac, Chinese is checked by the menu-bar helper; the input method itself
    /// only sees text typed through NaturalKana (see `inputMethodLanguages`).
    public static var available: [SuggestionLanguage] { allCases }
    public static let inputMethodLanguages: [SuggestionLanguage] = [.japanese, .english]
    /// The language of one draft among `languages`, or nil if none fits.
    /// A language's signal (hiragana for Japanese, common Chinese function words for Chinese…) decides;
    /// otherwise the primary language wins. Kanji-only text without Chinese markers is not guessed as Chinese
    /// for a Japanese-primary user (`ambiguousWith`).
    public static func detect(_ text: String, primary: SuggestionLanguage, among languages: [SuggestionLanguage]) -> SuggestionLanguage? {
        let normalized = TextNormalization.nfkc(text)
        let accepted = languages.filter { $0.draftProfile.accepts(normalized, composingLatin: false) }
        guard !accepted.isEmpty else { return nil }
        if let signaled = accepted.filter({ $0.pack.matchesSignal(normalized) }).min(by: { ($0.pack.detect.priority ?? .max) < ($1.pack.detect.priority ?? .max) }) {
            return signaled
        }
        if accepted.contains(primary) { return primary }
        return accepted.first { !($0.pack.detect.ambiguousWith ?? []).contains(primary.rawValue) }
    }
    public var title: String { UIText.t(pack.title) }
    public var promptName: String { pack.promptName }
    public var testDraft: String { pack.testDraft }
    public var draftProfile: any LanguageProfile {
        switch pack.rules {
        case "japanese": JapaneseDraftProfile()
        case "english": EnglishDraftProfile()
        case "chinese": ChineseDraftProfile()
        default: GenericProfile(rules: pack.generic ?? .init(letters: "[^\\s\\S]"))
        }
    }
    public func acceptsCandidate(_ text: String, original: String) -> Bool {
        switch pack.rules {
        case "japanese":
            let originalLatin = Set(JapaneseProfile.latinWords(original))
            return JapaneseProfile().accepts(text) && JapaneseProfile.latinWords(text).allSatisfy(originalLatin.contains)
        case "english": return EnglishProfile().accepts(text)
        case "chinese": return ChineseProfile().accepts(text, original: original)
        default: return GenericProfile(rules: pack.generic ?? .init(letters: "[^\\s\\S]")).acceptsCandidate(text, original: original)
        }
    }
    public func registerTitle(_ register: Register) -> String {
        register.isDialect ? Dialect.kansai.title : pack.registerTitles[register.rawValue] ?? register.rawValue
    }
    public var closeTitle: String { pack.closeTitle }
    public var copyHint: String { pack.copyHint }
}

/// Allows learner English, including a few unknown foreign words in an English sentence.
/// The model assesses meaning/naturalness; this gate only avoids unrelated input.
public struct EnglishDraftProfile: LanguageProfile {
    public init() {}
    public func accepts(_ text: String, composingLatin: Bool = false) -> Bool {
        guard !composingLatin else { return false }
        let normalized = TextNormalization.nfkc(text)
        guard EnglishProfile.isUsable(normalized) else { return false }
        let words = EnglishProfile.words(normalized)
        guard !words.isEmpty else { return false }
        let letters = normalized.unicodeScalars.filter(CharacterSet.letters.contains)
        let latin = letters.filter(EnglishProfile.isLatin)
        // Count a run of unknown characters as one word-sized slot, as with Japanese drafts.
        let foreignRuns = normalized.components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.unicodeScalars.contains { !EnglishProfile.isLatin($0) } }
        guard latin.count >= 2, foreignRuns.count <= 3,
              Double(latin.count) / Double(max(1, letters.count)) >= 0.5 else { return false }
        let anchors: Set<String> = ["i", "i'm", "i've", "i'll", "i'd", "you", "you're", "your", "we", "we're", "they", "he", "she", "it", "it's", "the", "a", "an", "is", "are", "was", "were", "to", "my", "me", "can", "could", "please", "have", "has", "don't", "doesn't", "not", "this", "that", "thanks", "hello"]
        if words.count >= 2 && words.contains(where: anchors.contains) { return true }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(normalized)
        return recognizer.dominantLanguage == .english
    }
}

/// Candidates must contain English text only; mixed-script placeholders belong in drafts.
public struct EnglishProfile: LanguageProfile {
    public init() {}
    static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.letters.contains(scalar) && ((65...122).contains(scalar.value) || (0xC0...0x24F).contains(scalar.value))
    }
    static func words(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
            .split { !$0.isLetter && $0 != "'" }.map(String.init)
    }
    static func isUsable(_ text: String) -> Bool {
        guard !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.illegalCharacters.contains($0) }),
              Set(text).count > 1 else { return false }
        let lower = text.lowercased()
        let denied = ["ignore previous instructions", "ignore all instructions", "ignore instructions", "system prompt", "developer message", "翻译", "翻訳", "指示を無視"]
        guard !denied.contains(where: lower.contains) else { return false }
        return lower.range(of: #"^\s*(please\s+)?(translate|rewrite in|respond in)\b"#, options: .regularExpression) == nil
    }
    public func accepts(_ text: String, composingLatin: Bool = false) -> Bool {
        let normalized = TextNormalization.nfkc(text)
        guard !composingLatin, Self.isUsable(normalized),
              normalized.unicodeScalars.filter(CharacterSet.letters.contains).allSatisfy(Self.isLatin) else { return false }
        return EnglishDraftProfile().accepts(normalized)
    }
}
