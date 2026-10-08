import Foundation

/// The sentence to check in another app's text field (Mac helper), and the UTF-16 range it occupies there.
public struct FieldDraft: Equatable, Sendable {
    public enum Problem: Error, Equatable, Sendable { case empty, multiline, tooLong }
    public let text: String
    /// UTF-16 range in the field's value, as Accessibility reports and replaces text.
    public let range: NSRange

    public init(text: String, range: NSRange) { self.text = text; self.range = range }

    /// A non-empty selection is checked as is (one line only); otherwise the whole line around the caret.
    /// Surrounding spaces stay out of the range so a replacement keeps the indentation.
    public static func make(value: String, selection: NSRange) -> Result<FieldDraft, Problem> {
        let utf16 = value.utf16
        guard selection.location != NSNotFound, selection.location >= 0, NSMaxRange(selection) <= utf16.count else { return .failure(.empty) }
        let source = value as NSString
        var range = selection
        if selection.length == 0 {
            // Surrogate halves (emoji) are never line breaks.
            func isNewline(_ index: Int) -> Bool { Unicode.Scalar(source.character(at: index)).map(CharacterSet.newlines.contains) ?? false }
            var start = selection.location, end = selection.location
            while start > 0, !isNewline(start - 1) { start -= 1 }
            while end < source.length, !isNewline(end) { end += 1 }
            range = NSRange(location: start, length: end - start)
        }
        let raw = source.substring(with: range)
        guard !raw.contains(where: \.isNewline) else { return .failure(.multiline) }
        let leading = raw.prefix(while: \.isWhitespace).utf16.count
        let trailing = raw.reversed().prefix(while: \.isWhitespace).reduce(0) { $0 + $1.utf16.count }
        guard leading + trailing < range.length else { return .failure(.empty) }
        let trimmed = NSRange(location: range.location + leading, length: range.length - leading - trailing)
        let text = source.substring(with: trimmed)
        // DraftSnapshot keeps the last 200 characters; replacing a longer line would drop its beginning.
        guard text.count <= 200 else { return .failure(.tooLong) }
        return .success(FieldDraft(text: text, range: trimmed))
    }
}
