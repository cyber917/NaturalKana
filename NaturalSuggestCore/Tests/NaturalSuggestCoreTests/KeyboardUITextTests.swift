import Testing
@testable import NaturalSuggestCore

struct KeyboardUITextTests {
    @Test func keyboardLabelsFollowLayoutLanguage() {
        for (language, back, space) in [
            (KeyboardSwitchLanguage.japanese, "戻る", "空白"),
            (.english, "Back", "space"),
            (.korean, "뒤로", "스페이스"),
            (.french, "Retour", "espace"),
            (.russian, "Назад", "пробел")
        ] {
            #expect(UIText.keyboard("返回", language: language) == back)
            #expect(UIText.keyboard("空格", language: language) == space)
        }
        #expect(UIText.keyboard("发送", language: .french) == "envoyer")
        #expect(UIText.keyboard("搜索", language: .russian) == "поиск")
        #expect(UIText.keyboard("不存在的文字", language: .english) == "不存在的文字")
    }

    @Test func keyboardTranslationsCoverEveryLayout() {
        let entries = UIText.table.filter { $0.value["fr"] != nil }
        #expect(entries.count >= 35)
        for (_, translations) in entries {
            for code in ["en", "ja", "ko", "fr", "ru"] {
                #expect(translations[code]?.isEmpty == false)
            }
        }
    }
}
