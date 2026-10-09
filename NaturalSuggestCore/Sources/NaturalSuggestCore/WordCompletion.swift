import Foundation

public enum CompletionLanguage: String, Codable, CaseIterable, Sendable {
    case french = "fr", russian = "ru", korean = "ko", chinese = "zh"
}

public enum CompletionWords {
    public static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character == "'" || character == "’" || character == "-"
    }

    public static func fragment(before text: String) -> String {
        String(text.reversed().prefix(while: isWordCharacter).reversed())
    }

    public static func previous(before text: String) -> String? {
        let end = text.dropLast(fragment(before: text).count)
        let trimmed = end.reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed()
        guard trimmed.count < end.count else { return nil }
        let word = fragment(before: String(trimmed))
        return word.isEmpty ? nil : word
    }

    public static func valid(_ word: String, language: CompletionLanguage) -> Bool {
        guard (1...40).contains(word.count), word.first?.isLetter == true, word.last?.isLetter == true, word.allSatisfy(isWordCharacter) else { return false }
        return word.unicodeScalars.allSatisfy { scalar in
            switch language {
            case .french: (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value) || (0xC0...0x24F).contains(scalar.value) || [0x27, 0x2019, 0x2D].contains(scalar.value)
            case .russian: (0x400...0x4FF).contains(scalar.value) || scalar == "-"
            case .korean: (0xAC00...0xD7A3).contains(scalar.value)
            case .chinese: (0x4E00...0x9FFF).contains(scalar.value)
            }
        }
    }

    public static func key(_ word: String, language: CompletionLanguage) -> String {
        guard language == .korean else {
            return word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: language.rawValue)).replacingOccurrences(of: "’", with: "'")
        }
        let initials = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
        let vowels = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
        let finals = Array(" ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")
        let compounds: [Character: String] = ["ㅘ":"ㅗㅏ", "ㅙ":"ㅗㅐ", "ㅚ":"ㅗㅣ", "ㅝ":"ㅜㅓ", "ㅞ":"ㅜㅔ", "ㅟ":"ㅜㅣ", "ㅢ":"ㅡㅣ", "ㄳ":"ㄱㅅ", "ㄵ":"ㄴㅈ", "ㄶ":"ㄴㅎ", "ㄺ":"ㄹㄱ", "ㄻ":"ㄹㅁ", "ㄼ":"ㄹㅂ", "ㄽ":"ㄹㅅ", "ㄾ":"ㄹㅌ", "ㄿ":"ㄹㅍ", "ㅀ":"ㄹㅎ", "ㅄ":"ㅂㅅ"]
        var result = ""
        for scalar in word.unicodeScalars {
            if (0xAC00...0xD7A3).contains(scalar.value) {
                let index = Int(scalar.value - 0xAC00)
                let letters = [initials[index / 588], vowels[index / 28 % 21]] + (index % 28 == 0 ? [] : [finals[index % 28]])
                for letter in letters { result += compounds[letter] ?? String(letter) }
            } else {
                let letter = Character(String(scalar))
                result += compounds[letter] ?? String(letter)
            }
        }
        return result
    }

    public static func casing(_ word: String, matching fragment: String) -> String {
        if fragment.count > 1, fragment == fragment.uppercased(), fragment != fragment.lowercased() { return word.uppercased() }
        if fragment.first?.isUppercase == true { return word.prefix(1).uppercased() + word.dropFirst() }
        return word
    }
}

public struct WordCompletionLexicon: Sendable {
    private struct Entry: Sendable { let word: String; let key: String }
    private let language: CompletionLanguage
    private let buckets: [Character: [Entry]]

    public init(words: [String], language: CompletionLanguage) {
        self.language = language
        var buckets: [Character: [Entry]] = [:]
        for word in words where CompletionWords.valid(word, language: language) {
            let key = CompletionWords.key(word, language: language)
            if let first = key.first { buckets[first, default: []].append(Entry(word: word, key: key)) }
        }
        self.buckets = buckets
    }

    public static func bundled(_ language: CompletionLanguage) -> Self {
        let url = Bundle.module.url(forResource: language.rawValue, withExtension: "txt", subdirectory: "KeyboardLexicons")
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return Self(words: text.split(separator: "\n").filter { !$0.hasPrefix("#") }.map(String.init), language: language)
    }

    public func suggestions(prefix: String, limit: Int = 8) -> [String] {
        let key = CompletionWords.key(prefix, language: language)
        guard !key.isEmpty, let first = key.first, limit > 0 else { return [] }
        return Array((buckets[first] ?? []).lazy.filter { $0.key.hasPrefix(key) && $0.word.lowercased() != prefix.lowercased() }.prefix(limit).map { CompletionWords.casing($0.word, matching: prefix) })
    }
}

public struct WordCompletionMemory: Codable, Sendable {
    public static let storageKey = "nk.keyboardWordMemory.v1"
    public static let resetKey = "nk.keyboardWordMemory.reset"
    public static let maximumEntries = 2000
    public struct Entry: Codable, Sendable {
        public var word: String
        public var language: CompletionLanguage
        public var uses: Int
        public var recent: Int
        public var previous: [String: Int]
    }
    public private(set) var entries: [Entry] = []
    private var clock = 0
    public init() {}

    private enum CodingKeys: String, CodingKey { case entries, clock }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode([Entry].self, forKey: .entries)
        var seen = Set<String>()
        entries = decoded.sorted { $0.recent > $1.recent }.filter {
            CompletionWords.valid($0.word, language: $0.language) && seen.insert($0.language.rawValue + ":" + $0.word.lowercased()).inserted
        }.prefix(Self.maximumEntries).map { entry in
            var entry = entry
            entry.uses = min(max(1, entry.uses), 1_000_000)
            entry.recent = max(0, entry.recent)
            entry.previous = Dictionary(uniqueKeysWithValues: entry.previous.filter {
                CompletionWords.valid($0.key, language: entry.language) && $0.value > 0
            }.sorted { $0.value > $1.value }.prefix(8).map { ($0.key, min($0.value, 1_000_000)) })
            return entry
        }
        clock = max(0, entries.map(\.recent).max() ?? 0)
    }

    public static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: storageKey), data.count < 2_000_000 else { return Self() }
        return (try? JSONDecoder().decode(Self.self, from: data)) ?? Self()
    }

    @discardableResult public func save(to defaults: UserDefaults, resetToken: String?) -> Bool {
        guard defaults.string(forKey: Self.resetKey) == resetToken, let data = try? JSONEncoder().encode(self) else { return false }
        defaults.set(data, forKey: Self.storageKey)
        return true
    }

    public static func clear(in defaults: UserDefaults) {
        defaults.set(UUID().uuidString, forKey: resetKey)
        defaults.removeObject(forKey: storageKey)
    }

    public mutating func forget(_ word: String, language: CompletionLanguage) {
        entries.removeAll { $0.language == language && $0.word.lowercased() == word.lowercased() }
    }

    public mutating func record(_ word: String, after previous: String?, language: CompletionLanguage) {
        guard CompletionWords.valid(word, language: language) else { return }
        clock = min(clock, Int.max - 1) + 1
        let index: Int
        if let existing = entries.firstIndex(where: { $0.language == language && $0.word.lowercased() == word.lowercased() }) {
            index = existing
        } else {
            entries.append(Entry(word: word, language: language, uses: 0, recent: clock, previous: [:]))
            index = entries.count - 1
        }
        entries[index].uses = min(max(0, entries[index].uses), 999_999) + 1
        entries[index].recent = clock
        if let previous, CompletionWords.valid(previous, language: language) {
            let key = previous.lowercased()
            entries[index].previous[key] = min(max(0, entries[index].previous[key] ?? 0), 999_999) + 1
            if entries[index].previous.count > 8, let least = entries[index].previous.min(by: { $0.value < $1.value })?.key {
                entries[index].previous.removeValue(forKey: least)
            }
        }
        if entries.count > Self.maximumEntries { entries.remove(at: entries.indices.min(by: { entries[$0].recent < entries[$1].recent })!) }
    }

    /// How often `word` was chosen; Chinese candidates use it to rank words the user picks.
    public func uses(of word: String, language: CompletionLanguage) -> Int {
        entries.first { $0.language == language && $0.word == word }?.uses ?? 0
    }

    public func suggestions(prefix: String, after previous: String?, language: CompletionLanguage, limit: Int = 8) -> [String] {
        let key = CompletionWords.key(prefix, language: language)
        let previous = previous?.lowercased()
        let matches = entries.filter { entry in
            guard entry.language == language, entry.word.lowercased() != prefix.lowercased() else { return false }
            if key.isEmpty { return previous.flatMap { entry.previous[$0] } != nil }
            return CompletionWords.key(entry.word, language: language).hasPrefix(key)
        }
        return Array(matches.sorted { lhs, rhs in
            let lhsContext = previous.flatMap { lhs.previous[$0] } ?? 0
            let rhsContext = previous.flatMap { rhs.previous[$0] } ?? 0
            if lhsContext != rhsContext { return lhsContext > rhsContext }
            if lhs.uses != rhs.uses { return lhs.uses > rhs.uses }
            return lhs.recent > rhs.recent
        }.prefix(max(0, limit)).map { CompletionWords.casing($0.word, matching: prefix) })
    }
}
