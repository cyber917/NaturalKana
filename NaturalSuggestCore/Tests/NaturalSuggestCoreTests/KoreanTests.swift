import Foundation
import Testing
@testable import NaturalSuggestCore

struct KoreanTests {
    private let korean = try! #require(SuggestionLanguage(rawValue: "korean"))
    private var settings: SuggestionSettings { var value = SuggestionSettings(); value.language = korean; return value }

    @Test func learnerDraftsPass() {
        for text in ["저는 어제 친구가 만났어요.", "내일 meeting이 있어서 늦어요", "ㅋㅋ 진짜 웃기다", "내일 会議가 있어요", "제 iPhone이 고장 났어요"] {
            #expect(korean.draftProfile.accepts(text, composingLatin: false), "Rejected: \(text)")
        }
        for text in ["今日は天気がいいですね", "I have a meeting tomorrow", "我明天有工作", "이 문장을 영어로 번역해 주세요", "ㅋㅋㅋㅋ"] {
            #expect(!korean.draftProfile.accepts(text, composingLatin: false), "Accepted: \(text)")
        }
    }
    @Test func candidatesStayInHangul() {
        #expect(korean.acceptsCandidate("저는 어제 친구를 만났어요.", original: "저는 어제 친구가 만났어요."))
        #expect(korean.acceptsCandidate("제 iPhone이 고장 났어요.", original: "제 iPhone이 고장 났어"))
        #expect(!korean.acceptsCandidate("내일 meeting이 있어요.", original: "내일 meeting이 있어요"))
        #expect(!korean.acceptsCandidate("내일 会議가 있어요.", original: "내일 会議가 있어요"))
        #expect(!korean.acceptsCandidate("明日は会議があります。", original: "내일 회의"))
    }
    @Test func compatibilityJamoAreShownAsTyped() throws {
        let json = #"{"assessment":"rewrite","suggestions":[{"text":"이 영화 진짜 꿀잼이야 ㅋㅋ","register":"casual"},{"text":"이 영화 진짜 재미있어요.","register":"polite"}]}"#
        let items = try ResponseValidator().validate(Data(json.utf8), draft: "이 영화 정말 재미있어요 ㅋㅋ", settings: settings)
        #expect(items.map(\.text) == ["이 영화 진짜 꿀잼이야 ㅋㅋ", "이 영화 진짜 재미있어요."])
        #expect(items.map(\.register) == [.casual, .polite])
        #expect(korean.registerTitle(.casual) == "반말" && korean.registerTitle(.polite) == "존댓말")
    }
    @Test func automaticLanguageFindsKorean() {
        let all = SuggestionLanguage.allCases
        #expect(SuggestionLanguage.detect("저는 어제 친구가 만났어요.", primary: .japanese, among: all) == korean)
        #expect(SuggestionLanguage.detect("내일 meeting이 있어서 늦어요", primary: .english, among: all) == korean)
        #expect(SuggestionLanguage.detect("今何にしていますか", primary: korean, among: all) == .japanese)
        #expect(SuggestionLanguage.detect("我明天有工作，所以请等一点我", primary: korean, among: all) == .chinese)
        #expect(SuggestionLanguage.detect("Yesterday I go to school.", primary: korean, among: all) == .english)
    }
    @Test func promptIsKorean() throws {
        let prompt = try PromptBuilder().make(draft: "저는 어제 친구가 만났어요.", settings: settings)
        #expect(prompt.system.contains("Korean phrasing assistant"))
        #expect(prompt.system.contains("Output only Korean candidates"))
        let payload = try #require(JSONSerialization.jsonObject(with: Data(prompt.user.utf8)) as? [String: Any])
        #expect(payload["language"] as? String == "korean")
        #expect(payload["dialect"] as? String == "off")
    }
    @Test func promptListsExactlyTheLatinWordsTheValidatorAllows() throws {
        let line = try #require(korean.pack.prompt.split(separator: "\n").first { $0.contains("Latin letters are otherwise allowed only in these established words:") })
        let listed = line.components(separatedBy: "established words: ")[1].components(separatedBy: ". ")[0].components(separatedBy: ", ")
        #expect(Set(listed) == Set(korean.pack.generic?.latinAllowlist ?? []))
    }
}
