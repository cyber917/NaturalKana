import Testing
@testable import NaturalSuggestCore

struct HangulComposerTests {
    /// Types `keys` into a field holding `text`; "⌫" is backspace and "|" ends the block (cursor moved).
    private func type(_ keys: String, into text: String = "") -> String {
        var composer = HangulComposer(); var field = text
        for key in keys {
            let edit: HangulComposer.Edit?
            switch key {
            case "⌫": edit = composer.deleteBackward() ?? HangulComposer.Edit(delete: 1, insert: "")
            case "|": composer.reset(); continue
            default:
                if HangulComposer.isJamo(key) { edit = composer.input(key) }
                else { composer.reset(); edit = HangulComposer.Edit(delete: 0, insert: String(key)) }
            }
            if let edit { field.removeLast(min(edit.delete, field.count)); field += edit.insert }
        }
        return field
    }

    @Test func syllablesAndWords() {
        #expect(type("ㅎㅏㄴㄱㅡㄹ") == "한글")
        #expect(type("ㅇㅏㄴㄴㅕㅇㅎㅏㅅㅔㅇㅛ") == "안녕하세요")
        #expect(type("ㄴㅏ ㅇㅓㅈㅔ ㅊㅣㄴㄱㅜ ㅁㅏㄴㄴㅏㅆㅇㅓ.") == "나 어제 친구 만났어.")
    }
    @Test func finalConsonantMovesToTheNextSyllable() {
        #expect(type("ㅎㅏㄴㅏ") == "하나")
        #expect(type("ㄷㅏㄹㄱㅏ") == "달가")       // ㄺ splits: ㄹ stays, ㄱ moves
        #expect(type("ㅇㅣㅆㅇㅓ") == "있어")       // ㅆ typed as one key stays a final
        #expect(type("ㅇㅣㅆㅓ") == "이써")         // …or moves whole
    }
    @Test func compoundVowelsAndFinals() {
        #expect(type("ㄱㅗㅏ") == "과")
        #expect(type("ㅇㅜㅣ") == "위")
        #expect(type("ㅇㅡㅣ") == "의")
        #expect(type("ㄷㅏㄹㄱ") == "닭")
        #expect(type("ㅇㅓㅂㅅ") == "없")
        #expect(type("ㅇㅓㅂㅅㅇㅓ") == "없어")
    }
    @Test func loneJamoStayAsTyped() {
        #expect(type("ㅋㅋㅋ") == "ㅋㅋㅋ")
        #expect(type("ㅠㅠ") == "ㅠㅠ")
        #expect(type("ㅏㅏ") == "ㅏㅏ")
        #expect(type("ㄸ") == "ㄸ")
        #expect(type("ㄱㅏㄸ") == "가ㄸ")           // ㄸ cannot end a syllable
    }
    @Test func backspaceRemovesOneKey() {
        #expect(type("ㅎㅏㄴ⌫") == "하")
        #expect(type("ㅎㅏㄴ⌫⌫") == "ㅎ")
        #expect(type("ㅎㅏㄴ⌫⌫⌫") == "")
        #expect(type("ㄱㅗㅏ⌫") == "고")
        #expect(type("ㄷㅏㄹㄱ⌫") == "달")
        #expect(type("ㅎㅏㄴㅏ⌫") == "하ㄴ")
        #expect(type("ㅎㅏㄴㅏ⌫⌫⌫") == "")       // past the block: ordinary backspace
    }
    @Test func onlyTheBlockBeingTypedIsEdited() {
        // Text already in the field is never merged: the cursor was moved there.
        #expect(type("ㅏ", into: "한") == "한ㅏ")
        #expect(type("ㅎㅏ|ㄴ") == "하ㄴ")
        var composer = HangulComposer()
        #expect(composer.input("ㄱ") == .init(delete: 0, insert: "ㄱ"))
        #expect(composer.input("ㅏ") == .init(delete: 1, insert: "가"))
        #expect(composer.isComposing && composer.composingText == "가")
        composer.reset()
        #expect(!composer.isComposing && composer.deleteBackward() == nil)
    }
}
