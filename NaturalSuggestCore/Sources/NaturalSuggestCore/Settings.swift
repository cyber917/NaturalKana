import Foundation
import CryptoKit

public enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case openAI, qwen, deepSeek, kimi, gemini, claude, custom
    public var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .qwen: UIText.t("Qwen / 百炼")
        case .deepSeek: "DeepSeek"
        case .kimi: "Kimi"
        case .gemini: "Gemini"
        case .claude: "Claude"
        case .custom: UIText.t("自定义")
        }
    }
    public var defaultConfiguration: ProviderConfiguration {
        let url: String
        switch self {
        case .openAI: url = "https://api.openai.com/v1"
        case .qwen: url = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
        case .deepSeek: url = "https://api.deepseek.com/v1"
        case .kimi: url = "https://api.moonshot.ai/v1"
        case .gemini: url = "https://generativelanguage.googleapis.com/v1beta/openai"
        case .claude: url = "https://api.anthropic.com/v1"
        case .custom: url = ""
        }
        var config = ProviderConfiguration(baseURL: url)
        if self == .claude { config.apiProtocol = .anthropicMessages }
        return config
    }
}
public enum ProviderProtocol: String, Codable, CaseIterable, Sendable { case chatCompletions, anthropicMessages }
public enum JSONResponseMode: String, Codable, CaseIterable, Sendable { case automatic, schema, object, prompt }
public enum TokenParameter: String, Codable, CaseIterable, Sendable { case automatic, maxTokens, maxCompletionTokens }
public enum RegisterPreference: String, Codable, CaseIterable, Sendable { case both, friendsCasual, politeCasual }
public enum SlangLevel: String, Codable, CaseIterable, Sendable { case off, light, trendy }
/// Regional dialect offered as an extra candidate group. Japanese only; add a case plus prompt examples per dialect.
public enum Dialect: String, Codable, CaseIterable, Sendable {
    case off, kansai
    public var title: String {
        switch self {
        case .off: UIText.t("关闭")
        case .kansai: "関西弁"
        }
    }
    /// The candidate register used for this dialect's group; nil when off.
    public var register: Register? {
        switch self {
        case .off: nil
        case .kansai: .kansai
        }
    }
}
/// Candidate group. Standard registers come first; dialect registers are separate groups after them.
public enum Register: String, Codable, CaseIterable, Sendable {
    case casual, polite, kansai
    public var isDialect: Bool { self == .kansai }
}
public struct Suggestion: Codable, Equatable, Hashable, Sendable {
    public var text: String
    public var register: Register
    public init(text: String, register: Register) { self.text = text; self.register = register }
}
public struct ProviderConfiguration: Codable, Hashable, Sendable {
    public var baseURL: String
    public var fastModel: String
    public var qualityModel: String
    // nil for models that do not support temperature. Never silently change a model.
    public var temperature: Double? = nil
    public var apiProtocol: ProviderProtocol = .chatCompletions
    public var responseMode: JSONResponseMode = .automatic
    public var tokenParameter: TokenParameter = .automatic
    public var disableThinking: Bool = false
    public init(baseURL: String, fastModel: String = "", qualityModel: String = "") {
        self.baseURL = baseURL; self.fastModel = fastModel; self.qualityModel = qualityModel
    }
    public func endpoint(_ path: String) throws -> URL {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let components = URLComponents(string: base), let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              !baseURL.contains("{"), let url = components.url else { throw SuggestionError.configuration }
        // Plain HTTP only for self-hosted models on this Mac/LAN (Ollama, llama.cpp, vLLM); the key would otherwise cross the internet unencrypted.
        if scheme == "http" && !Self.isLocalNetworkHost(host) { throw SuggestionError.insecureEndpoint }
        if url.path.hasSuffix("/" + path) { return url }
        guard !url.path.hasSuffix("/responses"), !url.path.hasSuffix("/messages"), !url.path.hasSuffix("/chat/completions") else { throw SuggestionError.configuration }
        return url.appendingPathComponent(path)
    }
    /// Hosts App Transport Security treats as local with NSAllowsLocalNetworking, plus private/link-local IP ranges.
    public static func isLocalNetworkHost(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") { return true }
        if host.contains(":") { return host == "::1" || host.hasPrefix("fc") || host.hasPrefix("fd") || ["fe8", "fe9", "fea", "feb"].contains(where: host.hasPrefix) }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ $0.map { (0...255).contains($0) } ?? false }) else { return !host.contains(".") }
        let a = octets[0]!, b = octets[1]!
        return a == 127 || a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) || (a == 169 && b == 254)
    }
    private enum CodingKeys: String, CodingKey { case baseURL, fastModel, qualityModel, temperature, disableThinking, apiProtocol, responseMode, tokenParameter }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try values.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        fastModel = try values.decodeIfPresent(String.self, forKey: .fastModel) ?? ""
        qualityModel = try values.decodeIfPresent(String.self, forKey: .qualityModel) ?? ""
        temperature = try values.decodeIfPresent(Double.self, forKey: .temperature)
        disableThinking = try values.decodeIfPresent(Bool.self, forKey: .disableThinking) ?? false
        apiProtocol = try values.decodeIfPresent(ProviderProtocol.self, forKey: .apiProtocol) ?? .chatCompletions
        responseMode = try values.decodeIfPresent(JSONResponseMode.self, forKey: .responseMode) ?? .automatic
        tokenParameter = try values.decodeIfPresent(TokenParameter.self, forKey: .tokenParameter) ?? .automatic
        // Older releases always sent temperature; omit it on migration unless explicitly configured in the new UI.
        if !values.contains(.apiProtocol) { temperature = nil }
    }

}
public struct SuggestionSettings: Codable, Hashable, Sendable {
    public var enabled = false
    public var consent = false
    public var language: SuggestionLanguage = .japanese
    /// Detect each draft's language; `language` stays the primary choice for ambiguous drafts.
    public var autoLanguage = false
    public var interfaceLanguage: InterfaceLanguage = .system
    public var extraKeyboardLayouts: [String] = []
    public var keyboardWordLearning: Bool = true
    /// `KeyboardTool` raw values kept beside the candidates.
    public var pinnedKeyboardTools: [String] = [KeyboardTool.emoji.rawValue]
    public func isPinned(_ tool: KeyboardTool) -> Bool { pinnedKeyboardTools.contains(tool.rawValue) }
    public mutating func setPinned(_ tool: KeyboardTool, _ pinned: Bool) {
        pinnedKeyboardTools.removeAll { $0 == tool.rawValue }
        if pinned { pinnedKeyboardTools = KeyboardTool.allCases.filter { $0 == tool || isPinned($0) }.map(\.rawValue) }
    }
    /// Nil follows all enabled layouts; a saved list selects and orders the quick switch cycle.
    public var keyboardSwitchOrder: [String]?
    public var availableKeyboardLanguages: [KeyboardSwitchLanguage] {
        [.japanese, .english] + enabledKeyboardLayouts.compactMap { KeyboardSwitchLanguage(rawValue: $0.rawValue) }
    }
    public var keyboardSwitchLanguages: [KeyboardSwitchLanguage] {
        let available = availableKeyboardLanguages
        guard let keyboardSwitchOrder else { return available }
        var seen: Set<KeyboardSwitchLanguage> = []
        let selected = keyboardSwitchOrder.compactMap(KeyboardSwitchLanguage.init(rawValue:))
            .filter { available.contains($0) && seen.insert($0).inserted }
        return selected.isEmpty ? available : selected
    }
    public mutating func setQuickSwitchLanguage(_ language: KeyboardSwitchLanguage, enabled: Bool) {
        var selected = keyboardSwitchLanguages
        guard availableKeyboardLanguages.contains(language) else { return }
        if enabled {
            if !selected.contains(language) { selected.append(language) }
        } else if selected.count > 1 {
            selected.removeAll { $0 == language }
        }
        keyboardSwitchOrder = selected.map(\.rawValue)
    }
    public mutating func moveQuickSwitchLanguage(_ language: KeyboardSwitchLanguage, by offset: Int) {
        var selected = keyboardSwitchLanguages
        guard let index = selected.firstIndex(of: language), selected.indices.contains(index + offset) else { return }
        selected.swapAt(index, index + offset)
        keyboardSwitchOrder = selected.map(\.rawValue)
    }
    /// Compatibility accessor for callers using the original Korean switch.
    public var koreanKeyboard: Bool {
        get { extraKeyboardLayouts.contains("korean") }
        set { setKeyboardLayout(.korean, enabled: newValue) }
    }
    public var enabledKeyboardLayouts: [ExtraKeyboardLayout] {
        ExtraKeyboardLayout.allCases.filter { extraKeyboardLayouts.contains($0.rawValue) }
    }
    public mutating func setKeyboardLayout(_ layout: ExtraKeyboardLayout, enabled: Bool) {
        extraKeyboardLayouts.removeAll { $0 == layout.rawValue }
        if enabled { extraKeyboardLayouts.append(layout.rawValue) }
    }
    public var provider: ProviderKind = .openAI
    public var openAI = ProviderConfiguration(baseURL: "https://api.openai.com/v1")
    public var qwen = ProviderConfiguration(baseURL: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1")
    public var additionalProviders: [String: ProviderConfiguration] = [:]
    public var highlightChanges = true
    public var qualityPartner: ProviderKind = .qwen
    public var registerPreference: RegisterPreference = .both
    public var slangLevel: SlangLevel = .light
    public var dialect: Dialect = .off
    /// The dialect actually requested; dialects only apply to Japanese suggestions.
    public var activeDialect: Dialect { language == .japanese ? dialect : .off }
    public var debounceMilliseconds = 600
    public var minimumLength = 4
    public static let suggestionCountRange = 1...10
    public var maximumSuggestions = 5
    public var suggestionLimit: Int { min(Self.suggestionCountRange.upperBound, max(Self.suggestionCountRange.lowerBound, maximumSuggestions)) }
    public var qualityMode = false
    public var dailyCap = 200 // 0 = unlimited. Counts every HTTP request, including judges.
    public var blockedApps: [String] = []
    public var acceptKeys = ["1", "2"] // Control modifier fixed to avoid ordinary typing conflicts.
    public init() {}
    public func configuration(for kind: ProviderKind) -> ProviderConfiguration {
        switch kind {
        case .openAI: openAI
        case .qwen: qwen
        default: additionalProviders[kind.rawValue] ?? kind.defaultConfiguration
        }
    }
    public mutating func setConfiguration(_ configuration: ProviderConfiguration, for kind: ProviderKind) {
        switch kind {
        case .openAI: openAI = configuration
        case .qwen: qwen = configuration
        default: additionalProviders[kind.rawValue] = configuration
        }
    }
    /// Settings for one draft: with autoLanguage, `language` becomes the detected language.
    /// Nil means the draft is not in any of `languages`.
    public func resolvingLanguage(for text: String, among languages: [SuggestionLanguage] = SuggestionLanguage.allCases) -> SuggestionSettings? {
        guard autoLanguage else { return self }
        guard let detected = SuggestionLanguage.detect(text, primary: language, among: languages) else { return nil }
        var copy = self; copy.language = detected
        return copy
    }
    public var comparisonProvider: ProviderKind { qualityPartner == provider ? (provider == .openAI ? .qwen : .openAI) : qualityPartner }
    public var fingerprint: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: (try? encoder.encode(self)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
    private enum LegacyCodingKeys: String, CodingKey { case koreanKeyboard }
    private enum CodingKeys: String, CodingKey { case enabled, consent, language, autoLanguage, interfaceLanguage, extraKeyboardLayouts, keyboardSwitchOrder, keyboardWordLearning, pinnedKeyboardTools, provider, openAI, qwen, additionalProviders, highlightChanges, qualityPartner, registerPreference, slangLevel, dialect, debounceMilliseconds, minimumLength, maximumSuggestions, qualityMode, dailyCap, blockedApps, acceptKeys }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        consent = try values.decodeIfPresent(Bool.self, forKey: .consent) ?? false
        // A language added by a newer release falls back to Japanese instead of discarding all settings.
        language = (try? values.decodeIfPresent(SuggestionLanguage.self, forKey: .language)) ?? .japanese
        autoLanguage = try values.decodeIfPresent(Bool.self, forKey: .autoLanguage) ?? false
        interfaceLanguage = (try? values.decodeIfPresent(InterfaceLanguage.self, forKey: .interfaceLanguage)) ?? .system
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        keyboardWordLearning = try values.decodeIfPresent(Bool.self, forKey: .keyboardWordLearning) ?? true
        pinnedKeyboardTools = try values.decodeIfPresent([String].self, forKey: .pinnedKeyboardTools) ?? [KeyboardTool.emoji.rawValue]
        let korean = try legacy.decodeIfPresent(Bool.self, forKey: .koreanKeyboard) ?? false
        extraKeyboardLayouts = try values.decodeIfPresent([String].self, forKey: .extraKeyboardLayouts) ?? (korean ? ["korean"] : [])
        keyboardSwitchOrder = try values.decodeIfPresent([String].self, forKey: .keyboardSwitchOrder)
        provider = try values.decodeIfPresent(ProviderKind.self, forKey: .provider) ?? .openAI
        openAI = try values.decodeIfPresent(ProviderConfiguration.self, forKey: .openAI) ?? ProviderKind.openAI.defaultConfiguration
        qwen = try values.decodeIfPresent(ProviderConfiguration.self, forKey: .qwen) ?? ProviderKind.qwen.defaultConfiguration
        additionalProviders = try values.decodeIfPresent([String: ProviderConfiguration].self, forKey: .additionalProviders) ?? [:]
        highlightChanges = try values.decodeIfPresent(Bool.self, forKey: .highlightChanges) ?? true
        qualityPartner = try values.decodeIfPresent(ProviderKind.self, forKey: .qualityPartner) ?? .qwen
        registerPreference = try values.decodeIfPresent(RegisterPreference.self, forKey: .registerPreference) ?? .both
        slangLevel = try values.decodeIfPresent(SlangLevel.self, forKey: .slangLevel) ?? .light
        // A dialect added by a newer release falls back to off instead of discarding all settings.
        dialect = (try? values.decodeIfPresent(Dialect.self, forKey: .dialect)) ?? .off
        debounceMilliseconds = try values.decodeIfPresent(Int.self, forKey: .debounceMilliseconds) ?? 600
        minimumLength = try values.decodeIfPresent(Int.self, forKey: .minimumLength) ?? 4
        maximumSuggestions = try values.decodeIfPresent(Int.self, forKey: .maximumSuggestions) ?? 5
        qualityMode = try values.decodeIfPresent(Bool.self, forKey: .qualityMode) ?? false
        dailyCap = try values.decodeIfPresent(Int.self, forKey: .dailyCap) ?? 200
        blockedApps = try values.decodeIfPresent([String].self, forKey: .blockedApps) ?? []
        acceptKeys = try values.decodeIfPresent([String].self, forKey: .acceptKeys) ?? ["1", "2"]
    }

}
public enum SuggestionError: Error, Sendable {
    case configuration, insecureEndpoint, missingKey, transport, invalidResponse, quota, timeout, truncated, refused, providerQuota
    case invalidModelID, modelUnavailable, unsupportedParameter
    case httpStatus(Int)
}
public enum InputFilterReason: Equatable, Sendable {
    case empty, tooShort(Int), composing, protectedField, language
    public var message: String {
        switch self {
        case .empty: UIText.t("尚未取得当前行文字；未联网")
        case .tooShort(let minimum): UIText.t("当前送检文字不足 %@ 字；未联网", "\(minimum)")
        case .composing: UIText.t("等待当前拼写转换完成；未联网")
        case .protectedField: UIText.t("当前输入框或应用禁止建议；未联网")
        case .language: UIText.t("当前句子与建议语言不符，或属于翻译/指令内容；未联网")
        }
    }
}
public enum Diagnostics: Equatable, Sendable {
    case idle, disabled, waiting, requesting, ready, natural, unsupportedDraft, noSuggestions, missingKey, configuration, insecureEndpoint, quota, unavailable
    case filtered(InputFilterReason), rejectedSuggestions(Int)
    case network, timeout, invalidResponse, truncated, refused, providerQuota
    case invalidModelID, modelUnavailable, unsupportedParameter
    case requiresFullAccess, contextUnavailable
    case httpStatus(Int)

    public init(error: Error) {
        if let error = error as? URLError {
            self = error.code == .timedOut ? .timeout : .network
            return
        }
        switch error {
        case SuggestionError.invalidModelID: self = .invalidModelID
        case SuggestionError.modelUnavailable: self = .modelUnavailable
        case SuggestionError.unsupportedParameter: self = .unsupportedParameter
        case SuggestionError.missingKey: self = .missingKey
        case SuggestionError.configuration: self = .configuration
        case SuggestionError.insecureEndpoint: self = .insecureEndpoint
        case SuggestionError.timeout: self = .timeout
        case SuggestionError.transport: self = .network
        case SuggestionError.invalidResponse, is DecodingError: self = .invalidResponse
        case SuggestionError.truncated: self = .truncated
        case SuggestionError.refused: self = .refused
        case SuggestionError.providerQuota: self = .providerQuota
        case SuggestionError.httpStatus(let code): self = .httpStatus(code)
        case SuggestionError.quota: self = .quota
        default: self = .unavailable
        }
    }

    // Only fixed messages and numeric HTTP status are exposed; never echo provider bodies or keys.
    public var message: String {
        switch self {
        case .idle: UIText.t("待机")
        case .disabled: UIText.t("功能关闭，或尚未同意发送草稿")
        case .filtered(let reason): reason.message
        case .rejectedSuggestions(let count): UIText.t("模型返回了 %@ 条候选，但都未通过格式、语言或重复内容检查", "\(count)")
        case .waiting: UIText.t("等待停顿")
        case .requesting: UIText.t("正在请求，请稍候；无需重复点击")
        case .ready: UIText.t("请求完成")
        case .natural: UIText.t("无需修改")
        case .unsupportedDraft: UIText.t("模型未能判断这句话")
        case .requiresFullAccess: UIText.t("请为键盘允许完全访问")
        case .contextUnavailable: UIText.t("当前输入位置暂不支持建议")
        case .noSuggestions: UIText.t("模型返回了空候选；这不代表原句一定自然")
        case .invalidModelID: UIText.t("模型 ID 不能含空格；请填写服务商 API 文档中的 ID")
        case .modelUnavailable: UIText.t("模型不存在或无访问权限，请核对 API 模型 ID")
        case .unsupportedParameter: UIText.t("模型不支持当前参数；请在接口兼容设置中调整 JSON 格式或输出参数")
        case .missingKey: UIText.t("请保存所选服务商的 API 密钥")
        case .configuration: UIText.t("请填写有效的接口地址（https://，本机或局域网服务可用 http://）和模型 ID")
        case .insecureEndpoint: UIText.t("公网接口必须使用 HTTPS；http:// 只支持本机或局域网地址（如 localhost、192.168.x.x、*.local）")
        case .quota: UIText.t("已达到本机今日请求上限")
        case .network: UIText.t("网络连接失败，请检查网络和接口地址后重试")
        case .timeout: UIText.t("请求超时（20 秒），请稍后重试；兼容的 Qwen 模型可开启非思考模式")
        case .invalidResponse: UIText.t("服务商已响应，但返回内容不符合候选 JSON 格式，请重试或检查模型兼容性")
        case .truncated: UIText.t("模型回复达到输出长度上限，内容被截断；可缩短草稿或使用非思考模式")
        case .refused: UIText.t("服务商拒绝生成此内容，请调整草稿后重试")
        case .providerQuota: UIText.t("服务商返回余额或额度不足，请检查服务商账户")
        case .httpStatus(401): UIText.t("密钥验证失败（HTTP 401），请检查密钥及接口地区")
        case .httpStatus(403): UIText.t("服务商拒绝访问（HTTP 403），请检查账户和模型权限")
        case .httpStatus(404): UIText.t("接口或模型不存在（HTTP 404），请检查接口地址和模型 ID")
        case .httpStatus(429): UIText.t("服务商限制了请求（HTTP 429），请稍后重试并检查账户限额")
        case .httpStatus(let code) where code == 400 || code == 422:
            UIText.t("请求参数被拒绝（HTTP %@），请检查模型是否支持 JSON Schema、非思考模式等参数", "\(code)")
        case .httpStatus(let code) where code >= 500:
            UIText.t("服务商暂时出错（HTTP %@），请稍后重试", "\(code)")
        case .httpStatus(let code): UIText.t("服务商请求失败（HTTP %@），请检查服务商配置", "\(code)")
        case .unavailable: UIText.t("请求未完成，发生了未识别的错误，请重试")
        }
    }
}
public enum TextNormalization {
    public static func nfkc(_ text: String) -> String { text.precomposedStringWithCompatibilityMapping }
}
public struct DraftSnapshot: Equatable, Sendable {
    public let text: String
    public let fieldID: String
    public let secure: Bool
    public let composingLatin: Bool
    public let appID: String
    public init(text: String, fieldID: String, secure: Bool = false, composingLatin: Bool = false, appID: String = "") {
        self.text = String(text.suffix(200)); self.fieldID = fieldID; self.secure = secure
        self.composingLatin = composingLatin; self.appID = appID
    }
    public static func currentLine(before: String, after: String) -> String {
        let start = before.lastIndex(where: { $0.isNewline }).map { before.index(after: $0) } ?? before.startIndex
        return String((before[start...] + after.prefix(while: { !$0.isNewline })).suffix(200))
    }
    /// Text between the caret and this draft's line end. Nil means the draft changed
    /// or the caret is outside the bounded replacement range.
    public func replacementSuffix(before: String, after: String) -> String? {
        let suffix = after.prefix(while: { !$0.isNewline })
        guard !text.isEmpty, Self.currentLine(before: before, after: after) == text,
              suffix.count <= text.count else { return nil }
        return String(suffix)
    }
}
