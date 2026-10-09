import Foundation

/// Small, offline supplements to the normal dictionaries. Order is editorial, not a usage statistic.
public struct ConversationLexicon: Sendable {
    public struct Entry: Sendable, Equatable {
        public let reading: String
        public let text: String
    }
    public struct Match: Sendable, Equatable {
        public let text: String
        /// The exact suffix to replace, including any spaces already typed.
        public let fragment: String
    }
    public let entries: [Entry]
    private let language: CompletionLanguage
    private let prefixes: [String: [Int]]
    private let keys: [String]

    public init(lines: [Substring], language: CompletionLanguage) {
        self.language = language
        var entries: [Entry] = [], keys: [String] = [], prefixes: [String: [Int]] = [:]
        var seen = Set<String>()
        for line in lines where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2 else { continue }
            let reading = String(fields[0]), text = String(fields[1])
            guard CompletionWords.validPhrase(reading, language: language),
                  CompletionWords.validPhrase(text, language: language), seen.insert(reading + "\t" + text).inserted else { continue }
            let key = CompletionWords.key(reading, language: language)
            let index = entries.count
            entries.append(Entry(reading: reading, text: text))
            keys.append(key)
            for count in 1...min(3, key.count) { prefixes[String(key.prefix(count)), default: []].append(index) }
        }
        self.entries = entries
        self.keys = keys
        self.prefixes = prefixes
    }

    public static func bundled(_ language: CompletionLanguage) -> Self {
        let url = Bundle.module.url(forResource: language.rawValue + "-chat", withExtension: "tsv", subdirectory: "KeyboardLexicons")
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return Self(lines: text.split(separator: "\n"), language: language)
    }

    /// Native marked-text keyboards replace only the composing part, not committed words.
    public func completions(composing: String, preceding: String = "", limit: Int = 2) -> [String] {
        guard !composing.isEmpty else { return [] }
        return matches(before: String(preceding.suffix(80)) + composing, limit: limit).compactMap { match in
            guard match.fragment.hasSuffix(composing) else { return nil }
            let committedCount = match.fragment.count - composing.count
            guard committedCount >= 0,
                  CompletionWords.key(String(match.text.prefix(committedCount)), language: language)
                    == CompletionWords.key(String(match.fragment.prefix(committedCount)), language: language) else { return nil }
            return String(match.text.dropFirst(committedCount))
        }
    }

    public func matches(before text: String, limit: Int = 3) -> [Match] {
        guard limit > 0 else { return [] }
        // Only a short, unfinished phrase in this sentence. Never match across punctuation/newlines.
        let tail = String(text.suffix(81).reversed().prefix { CompletionWords.isWordCharacter($0) || $0 == " " }.reversed())
        guard !tail.isEmpty, tail.count <= 80 else { return [] }
        var starts = [tail.startIndex]
        for index in tail.indices where tail[index] == " " { starts.append(tail.index(after: index)) }
        var result: [Match] = [], seen = Set<String>()
        for start in starts where start < tail.endIndex {
            let fragment = String(tail[start...])
            let key = CompletionWords.key(fragment, language: language)
            guard key.count >= 2 else { continue }
            for index in prefixes[String(key.prefix(3))] ?? [] where keys[index].hasPrefix(key) {
                let entry = entries[index]
                let value = language == .japanese ? entry.text : CompletionWords.casing(entry.text, matching: fragment)
                guard value != fragment, seen.insert(value).inserted else { continue }
                result.append(Match(text: value, fragment: fragment))
                if result.count == limit { return result }
            }
            // A longer matching phrase is more useful than isolated words at its end.
            if !result.isEmpty { break }
        }
        return result
    }
}
