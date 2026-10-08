import Foundation
import Testing
@testable import NaturalSuggestCore

struct FieldDraftTests {
    private func draft(_ value: String, _ location: Int, _ length: Int = 0) -> Result<FieldDraft, FieldDraft.Problem> {
        FieldDraft.make(value: value, selection: NSRange(location: location, length: length))
    }
    @Test func caretChecksItsWholeLine() throws {
        let value = "第一行\n  我明天有工作，所以请等一点我  \n第三行"
        let caret = (value as NSString).range(of: "等一点").location
        let result = try draft(value, caret).get()
        #expect(result.text == "我明天有工作，所以请等一点我")
        #expect((value as NSString).substring(with: result.range) == result.text)
    }
    @Test func caretAtEndOfFieldAndEmojiStayInTheLine() throws {
        let value = "今日は👨‍👩‍👧‍👦と遊んだ"
        #expect(try draft(value, value.utf16.count).get().text == value)
        #expect(try draft(value, 4).get().range == NSRange(location: 0, length: value.utf16.count))
    }
    @Test func selectionIsCheckedAsIs() throws {
        let value = "前半。我明天有工作。后半"
        let range = (value as NSString).range(of: "我明天有工作。")
        #expect(try draft(value, range.location, range.length).get() == FieldDraft(text: "我明天有工作。", range: range))
    }
    @Test func problemsAreReported() {
        #expect(draft("一行\n两行", 0, 5) == .failure(.multiline))
        #expect(draft("abc\n   \nxyz", 5) == .failure(.empty))
        #expect(draft("", 0) == .failure(.empty))
        #expect(draft("短い", 10) == .failure(.empty))
        #expect(draft(String(repeating: "あ", count: 201), 0) == .failure(.tooLong))
        #expect((try? draft(String(repeating: "あ", count: 200), 0).get())?.text.count == 200)
    }
}

#if os(macOS)
@testable import NaturalSuggestUI

@MainActor struct SettingsMigrationTests {
    @Test func legacySettingsMoveToTheSharedGroupOnce() throws {
        let legacyName = "NaturalKana.tests.legacy." + UUID().uuidString, groupName = "NaturalKana.tests.group." + UUID().uuidString
        let legacy = try #require(UserDefaults(suiteName: legacyName)), group = try #require(UserDefaults(suiteName: groupName))
        defer { legacy.removePersistentDomain(forName: legacyName); group.removePersistentDomain(forName: groupName) }
        legacy.set(Data("old".utf8), forKey: "nk.settings"); legacy.set(Data("words".utf8), forKey: "nk.personalLexicon"); legacy.set(7, forKey: "nk.budget.used")
        SuggestionModel.migrateLegacyDefaults(from: legacy, to: group)
        #expect(group.data(forKey: "nk.settings") == Data("old".utf8))
        #expect(group.data(forKey: "nk.personalLexicon") == Data("words".utf8))
        #expect(group.integer(forKey: "nk.budget.used") == 7)
        // Settings already in the group (for example saved by the helper) are never overwritten.
        legacy.set(Data("older".utf8), forKey: "nk.settings")
        SuggestionModel.migrateLegacyDefaults(from: legacy, to: group)
        #expect(group.data(forKey: "nk.settings") == Data("old".utf8))
    }
}
#endif
