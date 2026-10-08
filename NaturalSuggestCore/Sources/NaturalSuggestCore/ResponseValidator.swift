import Foundation

public struct ResponseValidator: Sendable {
    public init() {}
    public enum Assessment: String, Sendable { case natural, rewrite, unsupported }
    public struct Report: Sendable {
        public let suggestions: [Suggestion]
        public let receivedCount: Int
        public let assessment: Assessment?
        public var diagnostics: Diagnostics {
            if !suggestions.isEmpty { return .ready }
            if receivedCount > 0 { return .rejectedSuggestions(receivedCount) }
            if assessment == .natural { return .natural }
            if assessment == .unsupported { return .unsupportedDraft }
            return .noSuggestions
        }
    }
    public func validate(_ data: Data, draft: String, settings: SuggestionSettings) throws -> [Suggestion] {
        try inspect(data, draft: draft, settings: settings).suggestions
    }
    public func inspect(_ data: Data, draft: String, settings: SuggestionSettings) throws -> Report {
        guard data.count <= 32_768,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              Set(object.keys).isSubset(of: ["suggestions", "assessment"]),
              let rows = object["suggestions"] as? [[String: Any]], rows.count <= SuggestionSettings.suggestionCountRange.upperBound else { throw SuggestionError.invalidResponse }
        let assessment: Assessment?
        if let value = object["assessment"] {
            guard let raw = value as? String, let known = Assessment(rawValue: raw),
                  (known == .rewrite ? !rows.isEmpty : rows.isEmpty) else { throw SuggestionError.invalidResponse }
            assessment = known
        } else { assessment = nil } // Legacy empty replies are unknown, never a green check.
        let original = TextNormalization.nfkc(draft)
        var seen = Set<String>()
        let suggestions = rows.compactMap { row -> Suggestion? in
            guard Set(row.keys) == ["text", "register"], let raw = row["text"] as? String,
                  let registerName = row["register"] as? String, let register = Register(rawValue: registerName) else { return nil }
            let text = TextNormalization.nfkc(raw).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !text.contains(where: { $0.isNewline }),
                  !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.illegalCharacters.contains($0) }),
                  text != original, text.count <= 3 * original.count,
                  settings.language.acceptsCandidate(text, original: original),
                  // Dialect rows are their own group: only the selected dialect, never filtered by casual/polite preference.
                  register.isDialect ? register == settings.activeDialect.register :
                    (settings.registerPreference != .friendsCasual || register == .casual) &&
                    (settings.registerPreference != .politeCasual || register == .polite) else { return nil }
            // Reject newly introduced emoji/symbols. Numeric emoji properties alone are not sufficient.
            let emoji = text.unicodeScalars.filter { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
            guard emoji.allSatisfy({ original.unicodeScalars.contains($0) }), seen.insert(text).inserted else { return nil }
            // NFKC turns Chinese full-width punctuation (，：；) into ASCII; checks use it, display keeps the model's punctuation.
            let display = settings.language == .chinese ? raw.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespaces) : text
            return Suggestion(text: display, register: register)
        }.prefix(settings.suggestionLimit).map { $0 }
        // Keep model ranking within each register and use the same order for display, cache and acceptance.
        let grouped = Register.allCases.flatMap { register in suggestions.filter { $0.register == register } }
        return Report(suggestions: grouped, receivedCount: rows.count, assessment: assessment)
    }
}
