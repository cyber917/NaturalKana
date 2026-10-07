import Testing
@testable import NaturalSuggestCore

struct LineContextTests {
    private let draft = "仕事をした、keyboardを新しいfunctionをaddした"

    @Test func reportedMixedSentencePassesJapaneseGate() {
        #expect(JapaneseDraftProfile().accepts(draft))
        #expect(!JapaneseDraftProfile().accepts(draft, composingLatin: true))
        #expect(!JapaneseProfile().accepts(draft)) // Output still rejects untranslated words.
    }

    @Test func earlierLineIsReadWithoutAdjacentParagraphs() {
        let before = "Wait me a sec, I have to do some work.\n\n" + draft
        #expect(DraftSnapshot.currentLine(before: before, after: "\n次の段落") == draft)
        let snapshot = DraftSnapshot(text: draft, fieldID: "notes")
        #expect(snapshot.replacementSuffix(before: before, after: "\n次の段落") == "")
    }

    @Test func blankLineDoesNotReadTheNextSentence() {
        #expect(DraftSnapshot.currentLine(before: "前の行\n", after: "\n" + draft) == "")
        #expect(DraftSnapshot(text: "", fieldID: "notes").replacementSuffix(before: "前の行\n", after: "\n" + draft) == nil)
    }

    @Test func replacingFromInsideLinePreservesOtherLinesAndUnicode() throws {
        let original = "昨日👨‍👩‍👧‍👦とcafe\u{301}へ行く"
        let before = "上の行\n昨日"
        let after = "👨‍👩‍👧‍👦とcafe\u{301}へ行く\n下の行"
        let snapshot = DraftSnapshot(text: original, fieldID: "notes")
        let suffix = try #require(snapshot.replacementSuffix(before: before, after: after))
        #expect(suffix == "👨‍👩‍👧‍👦とcafe\u{301}へ行く")
        #expect(snapshot.replacementSuffix(before: before + suffix, after: String(after.dropFirst(suffix.count))) == "")
        let result = (before + suffix).dropLast(snapshot.text.count) + "昨日カフェへ行った" + after.dropFirst(suffix.count)
        #expect(result == "上の行\n昨日カフェへ行った\n下の行")
    }

    @Test func changedOrIncompleteContextCannotReplace() {
        let snapshot = DraftSnapshot(text: draft, fieldID: "notes")
        #expect(snapshot.replacementSuffix(before: draft + "！", after: "\n次の行") == nil)
        #expect(snapshot.replacementSuffix(before: String(draft.dropFirst()), after: "") == nil)
        #expect(snapshot.replacementSuffix(before: "別の行", after: "\n" + draft) == nil)
    }

    @Test func longLineDoesNotDeleteBeforeItsBoundedDraft() throws {
        let before = String(repeating: "あ", count: 250)
        let after = "した\n次の行"
        let snapshot = DraftSnapshot(text: DraftSnapshot.currentLine(before: before, after: after), fieldID: "notes")
        let suffix = try #require(snapshot.replacementSuffix(before: before, after: after))
        let result = (before + suffix).dropLast(snapshot.text.count) + "修正" + after.dropFirst(suffix.count)
        #expect(result == String(repeating: "あ", count: 52) + "修正\n次の行")
        #expect(snapshot.replacementSuffix(before: "", after: before + "した\n次の行") == nil)
    }

    @Test(arguments: ["\n", "\r\n", "\u{2028}", "\u{2029}"])
    func lineSeparatorsKeepTheSameBoundary(_ separator: String) {
        #expect(DraftSnapshot.currentLine(before: "前" + separator + "今", after: "から" + separator + "後") == "今から")
    }
}
