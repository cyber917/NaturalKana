import Foundation

/// Shared character checks for Simplified Chinese. Rules are plain script counts so the
/// Windows port (no NLLanguageRecognizer) can mirror them exactly.
enum ChineseText {
    static func isHiragana(_ s: Unicode.Scalar) -> Bool { (0x3041...0x3096).contains(s.value) }
    /// Latin words that may appear in Chinese candidates even when absent from the draft.
    static let latinAllowlist: Set<String> = ["OK", "AI", "App", "app", "APP", "PDF", "URL", "ID", "Wi", "Fi", "KTV", "emo", "yyds", "vlog"]
    /// Common Traditional or Japanese-only forms whose Simplified form is different.
    /// Candidates must be Simplified; drafts may contain them (learners often type Japanese kanji).
    static let notSimplified = CharacterSet(charactersIn: "們這說請謝飯嗎麼讓給還過聽歡話幫樣見來時國會學對個為與東車門開問間關長頭電體氣気動點認讀語書買賣覺親視駅図歩様済広辺発楽実経続紙網絡隣働売円応変戦検験録")
    /// Characters that are frequent in Chinese but rare in kanji-only Japanese.
    static let markers = CharacterSet(charactersIn: "的了吗呢吧们这那你我他她很没说么啊呀给让还过请谢")
    static let denied = ["翻译", "翻譯", "翻訳", "译成", "翻成", "忽略指令", "忽略之前", "系统提示", "提示词", "ignore instructions", "system prompt"]

    static func scalars(_ text: String) -> [Unicode.Scalar] {
        text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
    }
    /// Han share of the letters, counting each foreign word as at most two slots so that
    /// a long English placeholder does not outweigh the Chinese sentence around it.
    static func hanRatio(_ text: String) -> Double {
        let letters = scalars(text).filter { CharacterSet.letters.contains($0) }
        let han = letters.filter(JapaneseProfile.isHan).count
        let latin = letters.filter { $0.isASCII }.count
        let weighted = letters.count - latin + JapaneseProfile.latinWords(text).reduce(0) { $0 + min(2, $1.count) }
        return Double(han) / Double(max(1, weighted))
    }
    /// Hiragana carries Japanese grammar; a Chinese draft may only borrow a short word.
    static func looksJapanese(_ text: String) -> Bool {
        let all = scalars(text)
        let hiragana = all.filter(isHiragana).count
        let han = all.filter(JapaneseProfile.isHan).count
        return hiragana > 2 && hiragana * 3 > han
    }
}

/// Learner Chinese drafts. Japanese or English words used as placeholders are allowed;
/// standalone Japanese/English sentences and translation requests are not.
public struct ChineseDraftProfile: LanguageProfile {
    public init() {}
    public func accepts(_ text: String, composingLatin: Bool = false) -> Bool {
        guard !composingLatin else { return false }
        let normalized = TextNormalization.nfkc(text)
        guard !ChineseText.denied.contains(where: normalized.lowercased().contains),
              !normalized.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              Set(normalized).count > 1,
              ChineseText.scalars(normalized).filter(JapaneseProfile.isHan).count >= 2,
              !ChineseText.looksJapanese(normalized) else { return false }
        return ChineseText.hanRatio(normalized) >= 0.5
    }
}

/// Candidates must be Simplified Chinese: no kana, no Traditional/Japanese-only forms, and
/// Latin words only from the allowlist or as proper nouns already written in the draft.
public struct ChineseProfile: LanguageProfile {
    public init() {}
    public func accepts(_ text: String, composingLatin: Bool = false) -> Bool { accepts(text, original: "") }
    public func accepts(_ text: String, original: String) -> Bool {
        let normalized = TextNormalization.nfkc(text)
        guard !normalized.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.illegalCharacters.contains($0) }),
              !ChineseText.denied.contains(where: normalized.lowercased().contains),
              !normalized.unicodeScalars.contains(where: JapaneseProfile.isKana),
              !normalized.unicodeScalars.contains(where: ChineseText.notSimplified.contains),
              Set(normalized).count > 1,
              ChineseText.scalars(normalized).contains(where: JapaneseProfile.isHan) else { return false }
        // Brand names such as iPhone stay in Latin; lowercase placeholders (meeting, click) must be replaced.
        let properNouns = Set(JapaneseProfile.latinWords(TextNormalization.nfkc(original)).filter { $0.contains(where: \.isUppercase) })
        guard JapaneseProfile.latinWords(normalized).allSatisfy({ ChineseText.latinAllowlist.contains($0) || properNouns.contains($0) }) else { return false }
        return ChineseText.hanRatio(normalized) >= 0.6
    }
}
