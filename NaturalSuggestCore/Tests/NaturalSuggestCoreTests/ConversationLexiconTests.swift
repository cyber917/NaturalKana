import Foundation
import Testing
@testable import NaturalSuggestCore

struct ConversationLexiconTests {
    @Test func bundledChatResourcesAreValidAndUseful() throws {
        for (language, input, expected) in [(CompletionLanguage.english, "no wo", "no worries"), (.french, "ça ma", "ça marche"), (.russian, "ничего ст", "ничего страшного"), (.korean, "그럴 수", "그럴 수 있지"), (.japanese, "まじで", "マジで")] {
            let lexicon = ConversationLexicon.bundled(language)
            let count: Int = switch language {
            case .japanese: 120
            case .korean: 111
            default: 100
            }
            #expect(lexicon.entries.count == count)
            let match = try #require(lexicon.matches(before: input).first { $0.text == expected })
            #expect(match.fragment == input)
        }
        #expect(ConversationLexicon.bundled(.japanese).matches(before: "いまむか").contains { $0.text == "今向かってる" })
        #expect(ConversationLexicon.bundled(.korean).matches(before: "ㅋㅋ").contains { $0.text == "ㅋㅋㅋ" })
    }

    @Test func phrasesReplaceOnlyTheMatchedSuffix() throws {
        let lexicon = ConversationLexicon.bundled(.french)
        let before = "salut ça ma"
        let match = try #require(lexicon.matches(before: before).first { $0.text == "ça marche" })
        #expect(String(before.dropLast(match.fragment.count)) + match.text == "salut ça marche")
        #expect(lexicon.matches(before: "salut ca ma").contains { $0.text == "ça marche" && $0.fragment == "ca ma" })
        #expect(lexicon.matches(before: "ÇA MA").contains { $0.text == "ÇA MARCHE" })
        #expect(!lexicon.matches(before: "ça\nma").contains { $0.text == "ça marche" })
        #expect(!lexicon.matches(before: "ça, ma").contains { $0.text == "ça marche" })
        #expect(lexicon.matches(before: "").isEmpty)
        #expect(lexicon.matches(before: String(repeating: "a", count: 500)).isEmpty)
        #expect(lexicon.matches(before: "ça ma", limit: 0).isEmpty)
    }

    @Test func nativeCompositionDoesNotRepeatCommittedWords() {
        let english = ConversationLexicon.bundled(.english)
        #expect(english.completions(composing: "wo", preceding: "no ") == ["worries"])
        #expect(english.completions(composing: "wo", preceding: "Thanks! No ") == ["worries"])
        #expect(english.completions(composing: "", preceding: "no ").isEmpty)
        #expect(!english.completions(composing: "wo", preceding: "no\n").contains("worries"))
        #expect(ConversationLexicon.bundled(.japanese).completions(composing: "まじで").contains("マジで"))
    }

    @Test func malformedAndDuplicatePhrasesAreRejected() {
        let lexicon = ConversationLexicon(lines: ["# comment", "no worries\tno worries", "no worries\tno worries", "bad", "no\tworries\textra", "secret123\tsecret123", " a\ta", "a\tb@example.com"], language: .english)
        #expect(lexicon.entries.count == 1)
        #expect(!CompletionWords.validPhrase("a\nb", language: .english))
        #expect(!CompletionWords.validPhrase("a  b", language: .english))
        #expect(!CompletionWords.validPhrase("ㄱ", language: .korean))
    }

    @Test func selectedPhrasesCanBeLearnedAndForgotten() throws {
        var memory = WordCompletionMemory()
        memory.record("ça marche", after: "salut", language: .french)
        memory.record("ça marche", after: "salut", language: .french)
        let restored = try JSONDecoder().decode(WordCompletionMemory.self, from: JSONEncoder().encode(memory))
        #expect(restored.suggestions(prefix: "ca", after: "salut", language: .french).first == "ça marche")
        memory.forget("ça marche", language: .french)
        #expect(memory.suggestions(prefix: "ca", after: "salut", language: .french).isEmpty)
    }

    @Test func indexedWordPrefixesKeepOriginalFrequencyOrder() {
        let words = ["bonjour", "bonsoir", "bonne", "boulot", "bouffe", "bon"]
        let lexicon = WordCompletionLexicon(words: words, language: .french)
        for prefix in ["b", "bo", "bon", "bonj", "bou"] {
            let expected = Array(words.filter { $0.hasPrefix(prefix) && $0 != prefix }.prefix(8))
            #expect(Array(lexicon.suggestions(prefix: prefix).prefix(expected.count)) == expected)
        }
    }
}
