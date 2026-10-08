import Foundation

/// One suggestion language, read from Resources/Languages/<id>/: language.json, prompt.txt and an optional lexicon.jsonl.
/// The Windows app reads the same folders. Adding a language means adding a folder; languages whose checks are
/// not hand-tuned (`rules: "generic"`) describe their letters in language.json.
public struct LanguagePack: Decodable, Sendable {
    public struct Detection: Decodable, Sendable {
        /// Characters that identify the language when automatic detection has several candidates.
        public var signal: String?
        /// Lower wins when several languages show their signal.
        public var priority: Int?
        /// Without its signal, never chosen for users whose main language is one of these (kanji-only text is ambiguous).
        public var ambiguousWith: [String]?
    }
    /// Script checks for languages without hand-tuned rules.
    public struct GenericRules: Decodable, Sendable {
        /// Regex character class of the language's own letters, e.g. "[\\uAC00-\\uD7A3]".
        public var letters: String
        /// Minimum share of own letters in a draft; foreign words count as at most two letters.
        public var draftShare: Double?
        public var candidateShare: Double?
        public var minLetters: Int?
        /// Letters never allowed in a candidate, e.g. kana for Korean.
        public var forbidden: String?
        /// Latin words a candidate may contain when Latin is not among `letters`.
        public var latinAllowlist: [String]?
        /// Lowercase phrases that mark translation requests or instructions.
        public var denied: [String]?
        /// Required words for languages that share a script, such as French and English.
        public var requiredPattern: String?
    }

    public internal(set) var id = ""
    public var order: Int
    /// Simplified Chinese interface text; shown through UIText.
    public var title: String
    public var promptName: String
    /// BCP 47 code of the language.
    public var locale: String
    public var testDraft: String
    public var registerTitles: [String: String]
    public var closeTitle: String
    public var copyHint: String
    /// "japanese", "english" or "chinese" for the hand-tuned checks; "generic" uses `generic`.
    public var rules: String
    public var detect: Detection
    public var generic: GenericRules?
    /// Keep the model's full-width punctuation in candidates (checks still use NFKC).
    public var keepPunctuation: Bool?
    /// Typed through romaji/pinyin, so a trailing Latin letter means the IME is still composing.
    public var romanizedInput: Bool?
    public var windowsFont: String?
    public internal(set) var prompt = ""
    public internal(set) var lexicon = Lexicon(entries: [])

    private enum CodingKeys: String, CodingKey {
        case order, title, promptName, locale, testDraft, registerTitles, closeTitle, copyHint, rules, detect, generic, keepPunctuation, romanizedInput, windowsFont
    }

    /// All bundled packs, ordered for display.
    public static let bundled: [LanguagePack] = {
        guard let root = Bundle.module.url(forResource: "Languages", withExtension: nil, subdirectory: "Resources"),
              let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return folders.compactMap { try? load($0) }.sorted { ($0.order, $0.id) < ($1.order, $1.id) }
    }()
    static let byID = Dictionary(uniqueKeysWithValues: bundled.map { ($0.id, $0) })

    static func load(_ folder: URL) throws -> LanguagePack {
        var pack = try JSONDecoder().decode(LanguagePack.self, from: Data(contentsOf: folder.appendingPathComponent("language.json")))
        pack.id = folder.lastPathComponent
        pack.prompt = try String(contentsOf: folder.appendingPathComponent("prompt.txt"), encoding: .utf8)
        if let data = try? Data(contentsOf: folder.appendingPathComponent("lexicon.jsonl")) { pack.lexicon = (try? Lexicon(data: data)) ?? pack.lexicon }
        return pack
    }

    func matchesSignal(_ text: String) -> Bool {
        guard let signal = detect.signal else { return false }
        return text.range(of: signal, options: .regularExpression) != nil
    }
}

/// Draft and candidate checks driven by `LanguagePack.GenericRules`. Mirrored by GenericText in the Windows app.
public struct GenericProfile: LanguageProfile {
    let rules: LanguagePack.GenericRules
    public init(rules: LanguagePack.GenericRules) { self.rules = rules }

    private func isOwn(_ scalar: Unicode.Scalar) -> Bool { String(scalar).range(of: rules.letters, options: .regularExpression) != nil }
    private var latinIsOwn: Bool { isOwn("a") }
    private func denied(_ text: String) -> Bool { (rules.denied ?? []).contains(where: text.lowercased().contains) }
    private func matchesLanguage(_ text: String) -> Bool {
        rules.requiredPattern.map { text.range(of: $0, options: .regularExpression) != nil } ?? true
    }

    /// Share of own letters; with Latin foreign, each Latin word counts as at most two letters.
    func share(_ text: String) -> (own: Int, share: Double) {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let own = letters.filter(isOwn).count
        var total = letters.count
        if !latinIsOwn {
            let latin = letters.filter { $0.isASCII && !isOwn($0) }.count
            total += JapaneseProfile.latinWords(text).reduce(0) { $0 + min(2, $1.count) } - latin
        }
        return (own, Double(own) / Double(max(1, total)))
    }
    public func accepts(_ text: String, composingLatin: Bool = false) -> Bool {
        guard !composingLatin else { return false }
        let normalized = TextNormalization.nfkc(text)
        guard !denied(normalized), matchesLanguage(normalized), !normalized.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains), Set(normalized).count > 1 else { return false }
        let (own, share) = share(normalized)
        return own >= (rules.minLetters ?? 2) && share >= (rules.draftShare ?? 0.5)
    }
    public func acceptsCandidate(_ text: String, original: String) -> Bool {
        let normalized = TextNormalization.nfkc(text)
        guard !denied(normalized), matchesLanguage(normalized), Set(normalized).count > 1,
              !normalized.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.illegalCharacters.contains($0) }),
              rules.forbidden.map({ normalized.range(of: $0, options: .regularExpression) == nil }) ?? true else { return false }
        if !latinIsOwn {
            // Brand names keep their Latin spelling; lowercase placeholders must be written in the language.
            let properNouns = Set(JapaneseProfile.latinWords(TextNormalization.nfkc(original)).filter { $0.contains(where: \.isUppercase) })
            let allowed = Set(rules.latinAllowlist ?? [])
            guard JapaneseProfile.latinWords(normalized).allSatisfy({ allowed.contains($0) || properNouns.contains($0) }) else { return false }
        }
        let (own, share) = share(normalized)
        return own >= 1 && share >= (rules.candidateShare ?? 0.6)
    }
}
