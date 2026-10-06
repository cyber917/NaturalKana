import Foundation
import CryptoKit

public enum ProviderKind: String, Codable, CaseIterable, Sendable { case openAI, qwen }
public enum RegisterPreference: String, Codable, CaseIterable, Sendable { case both, friendsCasual, politeCasual }
public enum SlangLevel: String, Codable, CaseIterable, Sendable { case off, light, trendy }
public enum Register: String, Codable, Sendable { case casual, polite }
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
    public var temperature: Double? = 0.3
    public var disableThinking: Bool = false
    public init(baseURL: String, fastModel: String = "", qualityModel: String = "") {
        self.baseURL = baseURL; self.fastModel = fastModel; self.qualityModel = qualityModel
    }
    public func endpoint(_ path: String) throws -> URL {
        guard let components = URLComponents(string: baseURL), components.scheme == "https",
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              !baseURL.contains("{"), let url = components.url else { throw SuggestionError.configuration }
        return url.appendingPathComponent(path)
    }
}
public struct SuggestionSettings: Codable, Hashable, Sendable {
    public var enabled = false
    public var consent = false
    public var provider: ProviderKind = .openAI
    public var openAI = ProviderConfiguration(baseURL: "https://api.openai.com/v1")
    public var qwen = ProviderConfiguration(baseURL: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1")
    public var registerPreference: RegisterPreference = .both
    public var slangLevel: SlangLevel = .light
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
    public func configuration(for kind: ProviderKind) -> ProviderConfiguration { kind == .openAI ? openAI : qwen }
    public var fingerprint: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: (try? encoder.encode(self)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
}
public enum SuggestionError: Error, Sendable {
    case configuration, missingKey, transport, invalidResponse, quota, timeout, truncated, refused, providerQuota
    case httpStatus(Int)
}
public enum InputFilterReason: Equatable, Sendable {
    case empty, tooShort(Int), composing, protectedField, language
    public var message: String {
        switch self {
        case .empty: "尚未取得当前行文字；未联网"
        case .tooShort(let minimum): "当前送检文字不足 \(minimum) 字；未联网"
        case .composing: "等待罗马字转换成日语；未联网"
        case .protectedField: "当前输入框或应用禁止建议；未联网"
        case .language: "送检文字未识别为可处理的日语，或属于翻译/指令内容；未联网"
        }
    }
}
public enum Diagnostics: Equatable, Sendable {
    case idle, disabled, waiting, requesting, ready, noSuggestions, missingKey, configuration, quota, unavailable
    case filtered(InputFilterReason), rejectedSuggestions(Int)
    case network, timeout, invalidResponse, truncated, refused, providerQuota
    case httpStatus(Int)

    public init(error: Error) {
        if let error = error as? URLError {
            self = error.code == .timedOut ? .timeout : .network
            return
        }
        switch error {
        case SuggestionError.missingKey: self = .missingKey
        case SuggestionError.configuration: self = .configuration
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
        case .idle: "待机"
        case .disabled: "功能关闭，或尚未同意发送草稿"
        case .filtered(let reason): reason.message
        case .rejectedSuggestions(let count): "模型返回了 \(count) 条候选，但都未通过格式、语言或重复内容检查"
        case .waiting: "等待停顿"
        case .requesting: "正在请求，请稍候；无需重复点击"
        case .ready: "请求完成"
        case .noSuggestions: "模型返回了空候选；这不代表原句一定自然"
        case .missingKey: "请保存所选服务商的 API 密钥"
        case .configuration: "请填写有效的 HTTPS 地址和模型 ID"
        case .quota: "已达到本机今日请求上限"
        case .network: "网络连接失败，请检查网络和接口地址后重试"
        case .timeout: "请求超时（20 秒），请稍后重试；兼容的 Qwen 模型可开启非思考模式"
        case .invalidResponse: "服务商已响应，但返回内容不符合候选 JSON 格式，请重试或检查模型兼容性"
        case .truncated: "模型回复达到输出长度上限，内容被截断；可缩短草稿或使用非思考模式"
        case .refused: "服务商拒绝生成此内容，请调整草稿后重试"
        case .providerQuota: "服务商返回余额或额度不足，请检查服务商账户"
        case .httpStatus(401): "密钥验证失败（HTTP 401），请检查密钥及接口地区"
        case .httpStatus(403): "服务商拒绝访问（HTTP 403），请检查账户和模型权限"
        case .httpStatus(404): "接口或模型不存在（HTTP 404），请检查接口地址和模型 ID"
        case .httpStatus(429): "服务商限制了请求（HTTP 429），请稍后重试并检查账户限额"
        case .httpStatus(let code) where code == 400 || code == 422:
            "请求参数被拒绝（HTTP \(code)），请检查模型是否支持 JSON Schema、非思考模式等参数"
        case .httpStatus(let code) where code >= 500:
            "服务商暂时出错（HTTP \(code)），请稍后重试"
        case .httpStatus(let code): "服务商请求失败（HTTP \(code)），请检查服务商配置"
        case .unavailable: "请求未完成，发生了未识别的错误，请重试"
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
        String(((before.components(separatedBy: .newlines).last ?? "") +
                (after.components(separatedBy: .newlines).first ?? "")).suffix(200))
    }
}
