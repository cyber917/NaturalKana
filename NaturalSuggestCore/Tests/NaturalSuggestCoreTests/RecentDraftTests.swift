import Testing
@testable import NaturalSuggestCore

struct RecentDraftTests {
    @Test func committedTextSurvivesMissingHostContext() {
        var draft = RecentDraft()
        draft.recordCommit("今日ご飯を食べます")
        draft.recordCommit("あとは眠る")
        #expect(draft.text(hostPrefix: nil, composition: "") == "今日ご飯を食べますあとは眠る")
        #expect(JapaneseProfile().accepts(draft.text(hostPrefix: nil, composition: "")))
    }
    @Test func hostContextTakesPrecedenceAndDoesNotDuplicateComposition() {
        var draft = RecentDraft()
        draft.recordCommit("前の文章")
        #expect(draft.text(hostPrefix: "今から", composition: "寝ます") == "今から寝ます")
        #expect(draft.text(hostPrefix: "", composition: "こんにちは") == "こんにちは")
    }
    @Test func resetAndNewlinePreventCrossFieldHistory() {
        var draft = RecentDraft()
        draft.recordCommit("前の行\n今日")
        #expect(draft.text(hostPrefix: nil, composition: "は") == "今日は")
        draft.reset()
        #expect(draft.text(hostPrefix: nil, composition: "") == "")
    }
    @Test func boundRespectsUnicodeCharacters() {
        var draft = RecentDraft()
        draft.recordCommit(String(repeating: "𠮷", count: 250))
        let result = draft.text(hostPrefix: nil, composition: "です")
        #expect(result.count == 200)
        #expect(result.hasSuffix("𠮷です"))
    }
}
