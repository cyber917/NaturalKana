import Foundation
import Testing
@testable import NaturalSuggestCore

/// These tests never change UIText.language: tests run in parallel and other suites read it.
struct InterfaceLanguageTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Every UIText.t("…") literal in the shared package and the Mac patch.
    private static func sourceKeys() throws -> [String: String] {
        var keys: [String: String] = [:]
        let pattern = try NSRegularExpression(pattern: #"UIText\.t\("((?:[^"\\]|\\.)*)""#)
        func scan(_ text: String, _ origin: String) {
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let raw = String(text[Range(match.range(at: 1), in: text)!])
                let key = raw.replacingOccurrences(of: #"\\(.)"#, with: "$1", options: .regularExpression)
                keys[key] = origin
            }
        }
        let sources = root.appendingPathComponent("NaturalSuggestCore/Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        for file in files { scan(try String(contentsOf: file, encoding: .utf8), file.lastPathComponent) }
        let patch = try String(contentsOf: root.appendingPathComponent("patches/macos.patch"), encoding: .utf8)
        scan(patch.split(separator: "\n").filter { $0.hasPrefix("+") }.joined(separator: "\n"), "macos.patch")
        return keys
    }

    @Test func everyInterfaceStringHasEnglishAndJapanese() throws {
        let keys = try Self.sourceKeys()
        #expect(keys.count > 200)
        for (key, origin) in keys {
            let entry = UIText.table[key]
            #expect(entry?["en"]?.isEmpty == false, "No English for \(key) (\(origin))")
            #expect(entry?["ja"]?.isEmpty == false, "No Japanese for \(key) (\(origin))")
        }
    }
    @Test func translationsKeepEveryPlaceholder() {
        for (key, entry) in UIText.table {
            for placeholder in ["%@", "%.2f"] {
                let count = key.components(separatedBy: placeholder).count
                for (code, text) in entry { #expect(text.components(separatedBy: placeholder).count == count, "\(code) \(placeholder) in \(key)") }
            }
        }
    }
    @Test func translateFillsPlaceholdersInOrderAndFallsBackToChinese() {
        #expect(UIText.translate("建议上限：%@ 条", ["5"], into: .english) == "Max suggestions: 5")
        #expect(UIText.translate("建议上限：%@ 条", ["5"], into: .japanese) == "候補の上限：5 件")
        #expect(UIText.translate("建议上限：%@ 条", ["5"], into: .chinese) == "建议上限：5 条")
        #expect(UIText.translate("没有这一条：%@", ["x"], into: .english) == "没有这一条：x")
        // An argument containing %@ is inserted as is.
        #expect(UIText.translate("已删除“%@”。", ["%@"], into: .english) == "Deleted “%@”.")
        #expect(UIText.translate("主应用：共享配置可读，密钥%@。键盘：%@。", ["A"], into: .chinese) == "主应用：共享配置可读，密钥A。键盘：%@。")
    }
    @Test func settingsKeepTheInterfaceLanguage() throws {
        var settings = SuggestionSettings(); settings.interfaceLanguage = .japanese
        #expect(try JSONDecoder().decode(SuggestionSettings.self, from: JSONEncoder().encode(settings)).interfaceLanguage == .japanese)
        let legacy = try JSONDecoder().decode(SuggestionSettings.self, from: Data(#"{"consent":true}"#.utf8))
        #expect(legacy.interfaceLanguage == .system && !legacy.autoLanguage)
        let future = try JSONDecoder().decode(SuggestionSettings.self, from: Data(#"{"consent":true,"interfaceLanguage":"korean"}"#.utf8))
        #expect(future.interfaceLanguage == .system && future.consent)
    }
    @Test func languagesNameThemselves() {
        #expect(InterfaceLanguage.chinese.title == "中文")
        #expect(InterfaceLanguage.english.title == "English")
        #expect(InterfaceLanguage.japanese.title == "日本語")
        #expect(InterfaceLanguage.japanese.resolved == .japanese)
        #expect(InterfaceLanguage.system.resolved != .system)
    }
}

struct AutoLanguageTests {
    private let all = SuggestionLanguage.allCases
    @Test func hiraganaChineseWordsAndLatinDecide() {
        #expect(SuggestionLanguage.detect("今何にしていますか", primary: .chinese, among: all) == .japanese)
        #expect(SuggestionLanguage.detect("あとでmeetingがあるから、少し待って。", primary: .english, among: all) == .japanese)
        #expect(SuggestionLanguage.detect("我明天有工作，所以请等一点我", primary: .japanese, among: all) == .chinese)
        #expect(SuggestionLanguage.detect("我昨天在コンビニ买了饮料", primary: .japanese, among: all) == .chinese)
        #expect(SuggestionLanguage.detect("我明天要meeting", primary: .english, among: all) == .chinese)
        #expect(SuggestionLanguage.detect("Yesterday I go to school.", primary: .japanese, among: all) == .english)
        #expect(SuggestionLanguage.detect("I need to 预约 a table for two.", primary: .chinese, among: all) == .english)
    }
    @Test func kanjiOnlyTextIsNotGuessedAsChineseForJapaneseUsers() {
        #expect(SuggestionLanguage.detect("東京駅到着", primary: .japanese, among: all) == nil)
        #expect(SuggestionLanguage.detect("東京駅到着", primary: .chinese, among: all) == .chinese)
        #expect(SuggestionLanguage.detect("🙂🙂", primary: .japanese, among: all) == nil)
    }
    @Test func hostsOnlyDetectLanguagesTheyCanCheck() {
        // The Mac input method cannot see Chinese typed with another IME.
        #expect(SuggestionLanguage.detect("我明天有工作，所以请等一点我", primary: .japanese, among: [.japanese, .english]) == nil)
    }
    @Test func settingsResolveOnlyWhenAutomatic() {
        var settings = SuggestionSettings()
        #expect(settings.resolvingLanguage(for: "我明天有工作，所以请等一点我")?.language == .japanese)
        settings.autoLanguage = true
        #expect(settings.resolvingLanguage(for: "我明天有工作，所以请等一点我")?.language == .chinese)
        #expect(settings.resolvingLanguage(for: "Yesterday I go to school.")?.language == .english)
        #expect(settings.resolvingLanguage(for: "東京駅到着") == nil)
        var kansai = settings; kansai.dialect = .kansai
        #expect(kansai.resolvingLanguage(for: "我明天有工作，所以请等一点我")?.activeDialect == .off)
        #expect(kansai.resolvingLanguage(for: "今何にしていますか")?.activeDialect == .kansai)
    }
    @Test func promptFollowsTheDetectedLanguage() throws {
        var settings = SuggestionSettings(); settings.autoLanguage = true
        let resolved = try #require(settings.resolvingLanguage(for: "我明天有工作，所以请等一点我"))
        let prompt = try PromptBuilder().make(draft: "我明天有工作，所以请等一点我", settings: resolved)
        #expect(prompt.system.contains("Chinese phrasing assistant"))
    }
}
