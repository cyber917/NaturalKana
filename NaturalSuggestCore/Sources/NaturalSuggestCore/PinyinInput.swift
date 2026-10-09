import Foundation

/// A conversion of the typed pinyin, or of its first `consumed` letters.
public struct PinyinCandidate: Equatable, Sendable {
    public let text: String
    public let consumed: Int
    public init(text: String, consumed: Int) { self.text = text; self.consumed = consumed }
}

/// Pinyin conversion for the Chinese keyboard, from the bundled frequency-ordered dictionary.
/// Letters are lowercase a–z without separators; ü is typed as v.
public struct PinyinLexicon: Sendable {
    private struct Entry: Sendable { let word: String; let letters: String; let rank: Int }
    private let entries: [Entry]
    /// Letters → entries, most frequent first.
    private let exact: [String: [Int]]
    /// Entries ordered by letters, for prefix search.
    private let byLetters: [Int]
    private struct Node: Sendable {
        var children: [Int: Int] = [:]
        var entries: [Int] = []
        var edges: [(id: Int, child: Int)] = []
    }
    private struct Match {
        let entry: Int
        let end: Int
        let penalty: Double
        let corrected: Bool
    }
    private let longestKey: Int
    private let syllables: [[UInt8]]
    private let nodes: [Node]

    /// Each line is a word, a tab and its syllables separated by spaces, most frequent first.
    public init(lines: [Substring]) {
        var entries: [Entry] = []
        var exact: [String: [Int]] = [:]
        var syllables: [[UInt8]] = []
        var syllableIDs: [String: Int] = [:]
        var nodes = [Node()]
        for line in lines where !line.hasPrefix("#") {
            let parts = line.split(separator: "\t")
            guard parts.count == 2 else { continue }
            let letters = parts[1].replacingOccurrences(of: " ", with: "")
            guard !letters.isEmpty, letters.allSatisfy(Self.isLetter) else { continue }
            var node = 0
            for syllable in parts[1].split(separator: " ").map(String.init) {
                let id: Int
                if let existing = syllableIDs[syllable] { id = existing }
                else {
                    id = syllables.count
                    syllableIDs[syllable] = id
                    syllables.append(Array(syllable.utf8))
                }
                if let child = nodes[node].children[id] { node = child }
                else {
                    let child = nodes.count
                    nodes.append(Node())
                    nodes[node].children[id] = child
                    node = child
                }
            }
            nodes[node].entries.append(entries.count)
            exact[letters, default: []].append(entries.count)
            entries.append(Entry(word: String(parts[0]), letters: letters, rank: entries.count))
        }
        self.entries = entries
        self.exact = exact
        byLetters = entries.indices.sorted { entries[$0].letters < entries[$1].letters }
        longestKey = entries.map(\.letters.count).max() ?? 0
        self.syllables = syllables
        self.nodes = nodes.map { node in
            var node = node
            node.edges = node.children.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
            node.children = [:]
            return node
        }
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

        let matches = matches(Array(input.utf8))
        let sentences = sentences(letters.count, matches: matches, cost: cost, exactOnly: true).prefix(1)
            + sentences(letters.count, matches: matches, cost: cost)
        for sentence in sentences where result.count < limit && seen.insert(sentence).inserted {
            result.append(PinyinCandidate(text: sentence, consumed: letters.count))
        }
        for index in ranked(exact[input] ?? []) { add(index, consumed: letters.count) }
        for match in (matches.first ?? []).filter({ $0.end == letters.count }).sorted(by: {
            let left = cost($0.entry) + $0.penalty, right = cost($1.entry) + $1.penalty
            return left == right ? $0.entry < $1.entry : left < right
        }) { add(match.entry, consumed: letters.count) }
        for index in ranked(longer(than: input, cost: cost, limit: 6)) { add(index, consumed: letters.count) }
        for length in stride(from: letters.count - 1, through: 1, by: -1) {
            for index in ranked(exact[String(letters[..<length])] ?? []).prefix(8) { add(index, consumed: length) }
        }
        for match in (matches.first ?? []).filter({ $0.end < letters.count && !$0.corrected }).sorted(by: {
            if $0.end != $1.end { return $0.end > $1.end }
            return cost($0.entry) + $0.penalty < cost($1.entry) + $1.penalty
        }) { add(match.entry, consumed: match.end) }
        return result
    }

    private static let finalParticles: Set<String> = ["吗", "吧", "呢", "啊", "呀", "嘛", "啦", "哦", "哈"]

    /// Lower is better: frequent and often chosen words cost less.
    private static func cost(rank: Int, uses: Int) -> Double {
        log(Double(rank) + 100) - 1.5 * log(1 + Double(uses))
    }

    /// Match syllables as full spelling or initials. A single typo may be corrected per sentence.
    /// The trie shares syllable prefixes, so mixed spelling needs no exponential list of aliases.
    private func matches(_ input: [UInt8]) -> [[Match]] {
        let count = input.count
        // Exact spelling must stay available even when the mixed-spelling search reaches its bound.
        var result: [[Match]] = (0..<count).map { start in
            guard longestKey > 0 else { return [] }
            return ((start + 1)...min(count, start + longestKey)).flatMap { end in
                (exact[String(decoding: input[start..<end], as: UTF8.self)] ?? []).map {
                    Match(entry: $0, end: end, penalty: 0, corrected: false)
                }
            }
        }
        guard count <= 64 else { return result }
        for start in 0..<count {
            struct State {
                let node: Int
                let position: Int
                let penalty: Double
                let corrected: Bool
            }
            struct Key: Hashable { let node: Int; let position: Int; let corrected: Bool }
            var queue = [State(node: 0, position: start, penalty: 0, corrected: false)]
            var visited: [Key: Double] = [:]
            var cursor = 0
            // Very long runs of initials are ambiguous; bound the work on the keyboard thread.
            while cursor < queue.count && cursor < 4_096 {
                let state = queue[cursor]
                cursor += 1
                let key = Key(node: state.node, position: state.position, corrected: state.corrected)
                if let previous = visited[key], previous <= state.penalty { continue }
                visited[key] = state.penalty
                if state.penalty > 0 && (!state.corrected || state.position - start >= 4) {
                    for entry in nodes[state.node].entries {
                        result[start].append(Match(entry: entry, end: state.position,
                                                   penalty: state.penalty, corrected: state.corrected))
                    }
                }
                guard state.position < count else { continue }
                for (id, child) in nodes[state.node].edges {
                    let syllable = syllables[id]
                    let remaining = count - state.position
                    func append(_ length: Int, penalty: Double = 0, corrected: Bool = false) {
                        queue.append(State(node: child, position: state.position + length,
                                           penalty: state.penalty + penalty,
                                           corrected: state.corrected || corrected))
                    }
                    if remaining >= syllable.count,
                       input[state.position..<(state.position + syllable.count)].elementsEqual(syllable) {
                        append(syllable.count)
                    }
                    if syllable.count > 1, input[state.position] == syllable[0] {
                        append(1, penalty: 0.8)
                        if syllable.count > 2, syllable[1] == 104, remaining >= 2,
                           input[state.position + 1] == 104, [99, 115, 122].contains(syllable[0]) {
                            append(2, penalty: 0.8)
                        }
                    }
                    if remaining < syllable.count,
                       syllable.starts(with: input[state.position...]) {
                        append(remaining, penalty: 2)
                    }
                    guard !state.corrected, count >= 4, syllable.count >= 2, remaining >= syllable.count - 1 else { continue }
                    for length in max(1, syllable.count - 1)...min(remaining, syllable.count + 1) {
                        if Self.oneEdit(input[state.position..<(state.position + length)], syllable) {
                            append(length, penalty: 3, corrected: true)
                        }
                    }
                }
            }
        }
        return result
    }

    /// One missing, extra, substituted or transposed letter within a syllable.
    private static func oneEdit(_ typed: ArraySlice<UInt8>, _ expected: [UInt8]) -> Bool {
        let a = Array(typed), b = expected
        guard abs(a.count - b.count) <= 1 else { return false }
        var index = 0
        while index < min(a.count, b.count), a[index] == b[index] { index += 1 }
        if index == min(a.count, b.count) { return a.count != b.count }
        if a.count == b.count {
            if a.dropFirst(index + 1).elementsEqual(b.dropFirst(index + 1)) { return true }
            return index + 1 < a.count && a[index] == b[index + 1] && a[index + 1] == b[index]
                && a.dropFirst(index + 2).elementsEqual(b.dropFirst(index + 2))
        }
        if a.count > b.count { return a.dropFirst(index + 1).elementsEqual(b.dropFirst(index)) }
        return a.dropFirst(index).elementsEqual(b.dropFirst(index + 1))
    }

    /// Keep several complete paths: initials can represent more than one word or sentence.
    private func sentences(_ count: Int, matches: [[Match]], cost: (Int) -> Double, exactOnly: Bool = false) -> [String] {
        guard matches.count == count else { return [] }
        struct Path { let text: String; let cost: Double }
        func ranked(_ paths: [Path]) -> [Path] {
            var seen = Set<String>()
            return paths.sorted { $0.cost == $1.cost ? $0.text < $1.text : $0.cost < $1.cost }
                .filter { seen.insert($0.text).inserted }.prefix(24).map { $0 }
        }
        var paths = [[[Path]]](repeating: [[], []], count: count + 1)
        paths[0][0] = [Path(text: "", cost: 0)]
        for start in 0..<count {
            for budget in 0...1 {
                let previous = ranked(paths[start][budget])
                paths[start][budget] = []
                guard !previous.isEmpty else { continue }
                for match in matches[start] where !exactOnly || match.penalty == 0 {
                    let next = budget + (match.corrected ? 1 : 0)
                    guard next <= 1 else { continue }
                    let particle = match.end == count && match.penalty == 0
                        && Self.finalParticles.contains(entries[match.entry].word)
                    let addition = cost(match.entry) + match.penalty + (particle ? -2.5 : 1)
                    for path in previous {
                        paths[match.end][next].append(Path(text: path.text + entries[match.entry].word,
                                                          cost: path.cost + addition))
                    }
                }
            }
        }
        return ranked(paths[count][0] + paths[count][1]).map(\.text)
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
