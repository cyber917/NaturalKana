import Foundation
import NaturalSuggestCore

@main struct CLI {
    static func main() async {
        // JSONL interface uses the exact production gate, prompt and validator for evals.
        while let line = readLine() {
            do {
                guard let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let draft = object["draft"] as? String else { throw SuggestionError.configuration }
                var settings = SuggestionSettings(); settings.enabled = true; settings.consent = true
                settings.slangLevel = SlangLevel(rawValue: object["slang_level"] as? String ?? "light") ?? .light
                settings.registerPreference = RegisterPreference(rawValue: object["register_pref"] as? String ?? "both") ?? .both
                let accepted = JapaneseProfile().accepts(draft, composingLatin: object["composingLatin"] as? Bool ?? false) && draft.count >= 4
                var result: [String: Any] = ["gate": accepted, "suggestions": []]
                if let candidates = object["response"] {
                    let data = try JSONSerialization.data(withJSONObject: candidates)
                    result["suggestions"] = try ResponseValidator().validate(data, draft: draft, settings: settings).map { ["text": $0.text, "register": $0.register.rawValue] }
                } else if accepted, object["action"] as? String == "prompt" {
                    let prompt = try PromptBuilder(override: object["system_override"] as? String).make(draft: draft, settings: settings, lexicon: .bundled())
                    result["system"] = prompt.system; result["user"] = prompt.user
                } else if accepted, object["action"] as? String == "live" {
                    let configs = object["providers"] as? [String: [String: String]] ?? [:]
                    func client(_ kind: ProviderKind) throws -> CompatibleProvider {
                        guard let config = configs[kind.rawValue] else { throw SuggestionError.configuration }
                        let keyName = kind == .openAI ? "OPENAI_API_KEY" : "DASHSCOPE_API_KEY"
                        let key = ProcessInfo.processInfo.environment[keyName] ?? ""
                        var configuration = ProviderConfiguration(baseURL: config["baseURL"] ?? "", fastModel: config["fastModel"] ?? "", qualityModel: config["qualityModel"] ?? "")
                        if config["temperature"] == "omit" { configuration.temperature = nil }
                        configuration.disableThinking = config["disableThinking"] == "true"
                        return CompatibleProvider(kind: kind, configuration: configuration, key: key)
                    }
                    let kind = ProviderKind(rawValue: object["provider"] as? String ?? "openAI") ?? .openAI
                    let selected = try client(kind)
                    let quality = object["quality_mode"] as? Bool ?? false
                    let provider: any SuggestionProvider = quality ? try QualityProvider(first: client(.openAI), second: client(.qwen), judge: selected) : selected
                    let prompt = try PromptBuilder(override: object["system_override"] as? String).make(draft: draft, settings: settings, lexicon: .bundled())
                    let response = try await provider.suggest(prompt, quality: quality || object["slot"] as? String == "quality")
                    let items = try ResponseValidator().validate(response.json, draft: draft, settings: settings)
                    result["suggestions"] = items.map { ["text": $0.text, "register": $0.register.rawValue] }
                    result["input_tokens"] = response.inputTokens; result["output_tokens"] = response.outputTokens
                    result["network"] = true
                }
                let output = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .withoutEscapingSlashes])
                FileHandle.standardOutput.write(output + Data([10]))
            } catch { FileHandle.standardOutput.write(Data("{\"error\":\"invalid_input\",\"suggestions\":[]}\n".utf8)) }
        }
    }
}
