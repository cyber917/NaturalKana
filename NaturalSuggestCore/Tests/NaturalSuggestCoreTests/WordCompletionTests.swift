import Foundation
import Testing
@testable import NaturalSuggestCore

struct WordCompletionTests {
    @Test func bundledVocabularyCompletesAllThreeLanguages() {
        let french = WordCompletionLexicon.bundled(.french)
        #expect(french.suggestions(prefix: "bonj").contains("bonjour"))
        #expect(french.suggestions(prefix: "ecol").contains("école"))
        #expect(french.suggestions(prefix: "Bonj").contains("Bonjour"))
        #expect(french.suggestions(prefix: "BONJ").contains("BONJOUR"))
        let russian = WordCompletionLexicon.bundled(.russian)
        #expect(russian.suggestions(prefix: "приве").contains("привет"))
        let korean = WordCompletionLexicon.bundled(.korean)
        #expect(korean.suggestions(prefix: "안녕하").contains("안녕하세요"))
        #expect(korean.suggestions(prefix: "안녕ㅎ").contains("안녕하세요"))
    }

    @Test func correctionsAreOfflineAndPreserveExactPrefixes() {
        let french = WordCompletionLexicon(words: ["bonjour", "bonsoir", "bon", "bonne"], language: .french)
        for typed in ["bonjor", "bonjouur", "bonjuor", "bonjpur"] {
            #expect(french.suggestions(prefix: typed).contains("bonjour"))
        }
        #expect(french.suggestions(prefix: "bon").first == "bonjour")
        #expect(french.suggestions(prefix: "BONJUOR").contains("BONJOUR"))
        #expect(french.suggestions(prefix: "bonjour").isEmpty)
        #expect(french.suggestions(prefix: "bjnjpur").isEmpty)
        let russian = WordCompletionLexicon(words: ["привет"], language: .russian)
        #expect(russian.suggestions(prefix: "првиет") == ["привет"])
        let korean = WordCompletionLexicon(words: ["안녕하세요"], language: .korean)
        #expect(korean.suggestions(prefix: "안녕하세오") == ["안녕하세요"])
        #expect(korean.suggestions(prefix: "안녕ㅎ") == ["안녕하세요"])
    }

    @Test func hangulCompletionWorksDuringComposition() {
        let lexicon = WordCompletionLexicon(words: ["안녕하세요", "과일", "같이", "가나"], language: .korean)
        #expect(lexicon.suggestions(prefix: "ㅇ") == ["안녕하세요"])
        #expect(lexicon.suggestions(prefix: "고").contains("과일"))
        #expect(lexicon.suggestions(prefix: "간").contains("가나"))
        #expect(lexicon.suggestions(prefix: "과이") == ["과일"])
        #expect(lexicon.suggestions(prefix: "안녕하세요").isEmpty)
    }

    @Test func tokenBoundariesRespectPunctuationAndSentences() {
        #expect(CompletionWords.fragment(before: "salut l’éco") == "l’éco")
        #expect(CompletionWords.previous(before: "bonjour mon") == "bonjour")
        #expect(CompletionWords.previous(before: "bonjour ") == "bonjour")
        #expect(CompletionWords.previous(before: "bonjour. mon") == nil)
        #expect(CompletionWords.previous(before: "bonjour\nmon") == nil)
        #expect(!CompletionWords.valid("name@example.com", language: .french))
        #expect(!CompletionWords.valid("secret123", language: .french))
        #expect(!CompletionWords.valid("ㄱ", language: .korean))
        #expect(!CompletionWords.valid("bonjour", language: .russian))
    }

    @Test func memoryPersistsAndRanksFrequencyAndContext() throws {
        var memory = WordCompletionMemory()
        memory.record("naturellement", after: nil, language: .french)
        memory.record("naturalkana", after: nil, language: .french)
        memory.record("naturalkana", after: nil, language: .french)
        #expect(memory.suggestions(prefix: "natur", after: nil, language: .french).first == "naturalkana")
        memory.record("naturellement", after: "parler", language: .french)
        #expect(memory.suggestions(prefix: "natur", after: "parler", language: .french).first == "naturellement")
        let restored = try JSONDecoder().decode(WordCompletionMemory.self, from: JSONEncoder().encode(memory))
        #expect(restored.suggestions(prefix: "", after: "parler", language: .french) == ["naturellement"])
        #expect(restored.suggestions(prefix: "natur", after: nil, language: .russian).isEmpty)
        #expect(restored.suggestions(prefix: "", after: nil, language: .french).isEmpty)
    }

    @Test func memoryRejectsInvalidWordsAndBoundsStorage() {
        var memory = WordCompletionMemory()
        memory.record("person@example.com", after: nil, language: .french)
        memory.record("123456", after: nil, language: .french)
        #expect(memory.entries.isEmpty)
        for index in 0...WordCompletionMemory.maximumEntries {
            let suffix = String(Unicode.Scalar(0xAC00 + index)!)
            memory.record("단어" + suffix, after: nil, language: .korean)
        }
        #expect(memory.entries.count == WordCompletionMemory.maximumEntries)
        #expect(!memory.entries.contains { $0.word == "단어가" })
    }

    @Test func decodingSanitizesMemoryAndForgetRemovesOnlyChosenLanguage() throws {
        let data = Data(#"{"entries":[{"word":"bonjour","language":"fr","uses":-5,"recent":2,"previous":{"salut":9999999,"secret123":1}},{"word":"bonjour","language":"fr","uses":1,"recent":1,"previous":{}},{"word":"secret123","language":"fr","uses":1,"recent":3,"previous":{}}],"clock":-1}"#.utf8)
        var memory = try JSONDecoder().decode(WordCompletionMemory.self, from: data)
        #expect(memory.entries.count == 1)
        #expect(memory.entries[0].uses == 1)
        #expect(memory.entries[0].previous == ["salut": 1_000_000])
        memory.record("привет", after: nil, language: .russian)
        memory.forget("BONJOUR", language: .french)
        #expect(memory.suggestions(prefix: "bon", after: nil, language: .french).isEmpty)
        #expect(memory.suggestions(prefix: "при", after: nil, language: .russian) == ["привет"])
    }

    @Test func clearingMemoryRejectsAnOlderKeyboardSave() throws {
        let suite = "NaturalKana.tests.words." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var memory = WordCompletionMemory()
        memory.record("naturalkana", after: "bonjour", language: .french)
        #expect(memory.save(to: defaults, resetToken: nil))
        #expect(WordCompletionMemory.load(from: defaults).suggestions(prefix: "natur", after: nil, language: .french) == ["naturalkana"])
        WordCompletionMemory.clear(in: defaults)
        #expect(!memory.save(to: defaults, resetToken: nil))
        #expect(WordCompletionMemory.load(from: defaults).entries.isEmpty)
        let reset = try #require(defaults.string(forKey: WordCompletionMemory.resetKey))
        var newMemory = WordCompletionMemory.load(from: defaults)
        newMemory.record("bonjour", after: nil, language: .french)
        #expect(newMemory.save(to: defaults, resetToken: reset))
        #expect(WordCompletionMemory.load(from: defaults).entries.count == 1)
        defaults.set(Data("broken".utf8), forKey: WordCompletionMemory.storageKey)
        #expect(WordCompletionMemory.load(from: defaults).entries.isEmpty)
    }

    @Test func learningSettingMigratesAndRoundTrips() throws {
        let legacy = try JSONDecoder().decode(SuggestionSettings.self, from: Data("{}".utf8))
        #expect(legacy.keyboardWordLearning)
        var settings = legacy
        settings.keyboardWordLearning = false
        #expect(try JSONDecoder().decode(SuggestionSettings.self, from: JSONEncoder().encode(settings)).keyboardWordLearning == false)
    }
}
