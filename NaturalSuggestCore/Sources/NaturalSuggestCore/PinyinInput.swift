import Foundation

/// A conversion of the typed pinyin, or of its first `consumed` letters.
public struct PinyinCandidate: Equatable, Sendable {
    public let text: String
    public let consumed: Int
    public init(text: String, consumed: Int) { self.text = text; self.consumed = consumed }
}

/// Full-pinyin conversion for the Chinese keyboard, from the bundled frequency-ordered dictionary.
/// Letters are lowercase a–z without separators; ü is typed as v.
public struct PinyinLexicon: Sendable {
    private struct Entry: Sendable { let word: String; let letters: String; let rank: Int }
    private let entries: [Entry]
    /// Letters → entries, most frequent first.
    private let exact: [String: [Int]]
    /// Entries ordered by letters, for prefix search.
    private let byLetters: [Int]
    private let longestKey: Int

    /// Each line is a word, a tab and its syllables separated by spaces, most frequent first.
    public init(lines: [Substring]) {
        var entries: [Entry] = []
        var exact: [String: [Int]] = [:]
        for line in lines where !line.hasPrefix("#") {
            let parts = line.split(separator: "\t")
            guard parts.count == 2 else { continue }
            let letters = parts[1].replacingOccurrences(of: " ", with: "")
            guard !letters.isEmpty, letters.allSatisfy(Self.isLetter) else { continue }
            exact[letters, default: []].append(entries.count)
            entries.append(Entry(word: String(parts[0]), letters: letters, rank: entries.count))
        }
        self.entries = entries
        self.exact = exact
        byLetters = entries.indices.sorted { entries[$0].letters < entries[$1].letters }
        longestKey = entries.map(\.letters.count).max() ?? 0
    }

    public static func bundled() -> Self {
        let url = Bundle.module.url(forResource: "zh-pinyin", withExtension: "txt", subdirectory: "KeyboardLexicons")
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return Self(lines: text.split(separator: "\n"))
    }

    public static func isLetter(_ character: Character) -> Bool { ("a"..."z").contains(character) }

    /// Candidates for `input`: the whole input as a sentence, words spelled by all of it or starting with it,
    /// then words spelled by its first letters. `uses` reports how often the user chose a word.
    public func candidates(for input: String, uses: (String) -> Int = { _ in 0 }, limit: Int = 60) -> [PinyinCandidate] {
        guard !input.isEmpty, input.allSatisfy(Self.isLetter), limit > 0 else { return [] }
        let letters = Array(input)
        var result: [PinyinCandidate] = []
        var seen = Set<String>()
        func add(_ index: Int, consumed: Int) {
            if result.count < limit, seen.insert(entries[index].word).inserted {
                result.append(PinyinCandidate(text: entries[index].word, consumed: consumed))
            }
        }
        func cost(_ index: Int) -> Double { Self.cost(rank: entries[index].rank, uses: uses(entries[index].word)) }
        func ranked(_ indices: [Int]) -> [Int] { indices.map { ($0, cost($0)) }.sorted { $0.1 < $1.1 }.map(\.0) }

        if let sentence = sentence(letters, cost: cost), seen.insert(sentence).inserted {
            result.append(PinyinCandidate(text: sentence, consumed: letters.count))
        }
        for index in ranked(exact[input] ?? []) { add(index, consumed: letters.count) }
        for index in ranked(longer(than: input, cost: cost, limit: 6)) { add(index, consumed: letters.count) }
        for length in stride(from: letters.count - 1, through: 1, by: -1) {
            for index in ranked(exact[String(letters[..<length])] ?? []).prefix(8) { add(index, consumed: length) }
        }
        return result
    }

    private static let finalParticles: Set<String> = ["吗", "吧", "呢", "啊", "呀", "嘛", "啦", "哦", "哈"]

    /// Lower is better: frequent and often chosen words cost less.
    private static func cost(rank: Int, uses: Int) -> Double {
        log(Double(rank) + 100) - 1.5 * log(1 + Double(uses))
    }

    /// The cheapest split of all letters into dictionary words; the last word may be spelled only in part.
    /// Nil unless it needs two or more words, since single words are listed on their own.
    private func sentence(_ letters: [Character], cost: (Int) -> Double) -> String? {
        let count = letters.count
        var best = [Double](repeating: .infinity, count: count + 1)
        var back = [(start: Int, entry: Int)?](repeating: nil, count: count + 1)
        best[0] = 0
        for start in 0..<count where best[start].isFinite {
            for end in (start + 1)...min(count, start + longestKey) {
                guard let words = exact[String(letters[start..<end])],
                      let word = words.min(by: { cost($0) < cost($1) }) else { continue }
                // Each extra word costs a little, so a known phrase beats the same letters split up.
                // A sentence-final particle is likelier at the end than a word spelled the same (吧, not 把).
                let particle = end == count ? words.first(where: { Self.finalParticles.contains(entries[$0].word) }) : nil
                let total = particle.map { best[start] + cost($0) - 2.5 } ?? best[start] + cost(word) + 1
                if total < best[end] { best[end] = total; back[end] = (start, particle ?? word) }
            }
        }
        var end = count
        var lowest = best[count]
        var tail: Int?
        // Unfinished last syllable: complete it with the best word starting with the remaining letters.
        for start in 0..<count where best[start].isFinite {
            guard let word = longer(than: String(letters[start...]), cost: cost, limit: 1).first else { continue }
            let total = best[start] + cost(word) + 3
            if total < lowest { lowest = total; end = start; tail = word }
        }
        guard lowest.isFinite else { return nil }
        var words: [String] = tail.map { [entries[$0].word] } ?? []
        while end > 0, let step = back[end] {
            words.insert(entries[step.entry].word, at: 0)
            end = step.start
        }
        return words.count > 1 ? words.joined() : nil
    }

    /// Words whose letters start with `prefix` and are longer, cheapest first.
    private func longer(than prefix: String, cost: (Int) -> Double, limit: Int) -> [Int] {
        var low = 0, high = byLetters.count
        while low < high {
            let middle = (low + high) / 2
            if entries[byLetters[middle]].letters < prefix { low = middle + 1 } else { high = middle }
        }
        var found: [(Int, Double)] = []
        for index in byLetters[low...].prefix(20_000) {
            let letters = entries[index].letters
            guard letters.hasPrefix(prefix) else { break }
            if letters.count > prefix.count { found.append((index, cost(index))) }
        }
        return found.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
    }
}
