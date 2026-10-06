import Foundation

public struct SuggestionSpan: Equatable, Sendable {
    public let text: String
    public let changed: Bool
}
/// Compare graphemes locally. No draft storage or additional model request.
public enum SuggestionDiff {
    public static func spans(original: String, candidate: String) -> [SuggestionSpan] {
        if original == candidate { return [SuggestionSpan(text: candidate, changed: false)] }
        let old = Array(TextNormalization.nfkc(original)), new = Array(candidate)
        guard !old.isEmpty, old.count <= 200, new.count <= 600 else {
            return [SuggestionSpan(text: candidate, changed: false)]
        }
        let width = new.count + 1
        var lengths = [Int](repeating: 0, count: (old.count + 1) * width)
        for i in old.indices.reversed() {
            for j in new.indices.reversed() {
                lengths[i * width + j] = old[i] == new[j] ? 1 + lengths[(i + 1) * width + j + 1] :
                    max(lengths[(i + 1) * width + j], lengths[i * width + j + 1])
            }
        }
        var changed = [Bool](repeating: true, count: new.count)
        var i = 0, j = 0
        while i < old.count && j < new.count {
            if old[i] == new[j] { changed[j] = false; i += 1; j += 1 }
            else if lengths[(i + 1) * width + j] >= lengths[i * width + j + 1] { i += 1 }
            else { j += 1 }
        }
        // A deletion has no inserted text to color; mark its surviving boundary.
        if !changed.contains(true), old != new, !new.isEmpty {
            let firstDifference = zip(old, new).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? new.count - 1
            changed[min(firstDifference, new.count - 1)] = true
        }
        var result: [SuggestionSpan] = []
        for index in new.indices {
            if let last = result.last, last.changed == changed[index] {
                result[result.count - 1] = SuggestionSpan(text: last.text + String(new[index]), changed: last.changed)
            } else { result.append(SuggestionSpan(text: String(new[index]), changed: changed[index])) }
        }
        return result
    }
}
