import SwiftUI
import NaturalSuggestCore

@MainActor public final class SuggestionModel: ObservableObject {
    @Published public var settings: SuggestionSettings
    @Published public private(set) var suggestions: [Suggestion] = []
    @Published public private(set) var status: Diagnostics = .idle
    @Published public var settingsMessage = ""
    @Published public private(set) var personalEntries: [PersonalLexiconEntry] = []
    @Published public private(set) var timingText = ""
    private var personalData: Data?
    public var onStatusChange: ((Diagnostics) -> Void)?
    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private let engine: SuggestionEngine?
    public init() {
        let group = Bundle.main.object(forInfoDictionaryKey: "NaturalKanaAppGroup") as? String
        let storage = group.flatMap(UserDefaults.init(suiteName:)) ?? UserDefaults(suiteName: "NaturalKana")!
        defaults = storage
        keychain = KeychainStore(accessGroup: Bundle.main.object(forInfoDictionaryKey: "NaturalKanaKeychainGroup") as? String)
        settings = defaults.data(forKey: "nk.settings").flatMap { try? JSONDecoder().decode(SuggestionSettings.self, from: $0) } ?? SuggestionSettings()
        engine = (try? PromptBuilder()).map { SuggestionEngine(budget: DailyBudget(defaults: storage), prompt: $0) }
        engine?.onChange = { [weak self] items, state in
            guard let self else { return }
            suggestions = items; status = state
            timingText = engine?.cacheHit == true ? "缓存命中，无需联网" : engine?.requestSeconds.map { String(format: "本次联网耗时 %.2f 秒", $0) } ?? ""
            onStatusChange?(state)
        }
        reloadPersonalLexicon()
    }
    private func reloadPersonalLexicon() {
        let data = defaults.data(forKey: "nk.personalLexicon")
        guard data != personalData else { return }
        personalData = data
        personalEntries = data.flatMap { try? PersonalLexicon.parse($0, json: true) } ?? []
        engine?.setPersonalLexicon(personalEntries)
    }
    public func importPersonalLexicon(_ entries: [PersonalLexiconEntry]) throws {
        reloadPersonalLexicon()
        try storePersonalLexicon(PersonalLexicon.merge(existing: personalEntries, incoming: entries))
    }
    public func removePersonalEntry(_ id: String) throws {
        reloadPersonalLexicon()
        try storePersonalLexicon(personalEntries.filter { $0.id != id })
    }
    private func storePersonalLexicon(_ entries: [PersonalLexiconEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        defaults.set(data, forKey: "nk.personalLexicon")
        personalData = data; personalEntries = entries; engine?.setPersonalLexicon(entries)
    }
    public func useResponsiveSettings() {
        settings.debounceMilliseconds = 300; settings.qualityMode = false
        if settings.provider == .qwen { settings.qwen.disableThinking = true }
    }
    public func reload() {
        reloadPersonalLexicon()
        if let data = defaults.data(forKey: "nk.settings"), let new = try? JSONDecoder().decode(SuggestionSettings.self, from: data), new != settings {
            engine?.cancel(clearCache: true); settings = new
        }
    }
    @discardableResult public func save(openAIKey: String = "", qwenKey: String = "") -> Bool {
        do {
            if !openAIKey.isEmpty { try keychain.write(openAIKey, account: ProviderKind.openAI.rawValue) }
            if !qwenKey.isEmpty { try keychain.write(qwenKey, account: ProviderKind.qwen.rawValue) }
            defaults.set(try JSONEncoder().encode(settings), forKey: "nk.settings")
            engine?.cancel(clearCache: true); settingsMessage = "已保存。密钥保存在系统钥匙串。"
            return true
        } catch { settingsMessage = "保存失败。请检查签名与钥匙串共享权限。"; return false }
    }
    public func testSuggestion() {
        update(DraftSnapshot(text: "今日は仕事があるから、少し待ってください。", fieldID: "settings-test"), explicit: true)
    }
    public func deleteKey(_ kind: ProviderKind) {
        do { try keychain.write("", account: kind.rawValue); engine?.cancel(clearCache: true); settingsMessage = "密钥已删除。" }
        catch { settingsMessage = "无法删除密钥。" }
    }
    public func cancel() { engine?.cancel(clearCache: true) }
    public func invalidate() { engine?.cancel() }
    public func update(_ snapshot: DraftSnapshot, explicit: Bool = false) {
        reload()
        func client(_ kind: ProviderKind) -> CompatibleProvider {
            CompatibleProvider(kind: kind, configuration: settings.configuration(for: kind), key: (try? keychain.read(kind.rawValue)) ?? "")
        }
        let provider: any SuggestionProvider
        if settings.qualityMode { provider = QualityProvider(first: client(.openAI), second: client(.qwen), judge: client(settings.provider)) }
        else { provider = client(settings.provider) }
        guard let engine else {
            status = .unavailable; onStatusChange?(.unavailable); return
        }
        engine.update(snapshot, settings: settings, provider: provider, explicit: explicit)
    }
    public func accept(_ index: Int, snapshot: DraftSnapshot) -> String? {
        reload()
        guard settings.enabled, settings.consent, !settings.blockedApps.contains(snapshot.appID) else { cancel(); return nil }
        return engine?.accept(index: index, current: snapshot)
    }
    public var statusText: String { status.message }
    public var receivedCandidateCount: Int? { engine?.receivedCandidateCount }
}
public struct SuggestionStrip: View {
    public let suggestions: [Suggestion]
    public let accept: (Int) -> Void
    public let copiesOnly: Bool
    public init(suggestions: [Suggestion], copiesOnly: Bool = false, accept: @escaping (Int) -> Void) {
        self.suggestions = suggestions; self.copiesOnly = copiesOnly; self.accept = accept
    }
    public var body: some View {
        if !suggestions.isEmpty {
            VStack(spacing: 0) {
              if copiesOnly { Text("クリックでコピー・元の文を選択して貼り付け").font(.caption).foregroundStyle(.secondary).padding(6) }
              ScrollView(.vertical) {
              VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(suggestions.prefix(SuggestionSettings.suggestionCountRange.upperBound).enumerated()), id: \.offset) { index, suggestion in
                    if index == 0 || suggestions[index - 1].register != suggestion.register {
                        Text(suggestion.register == .casual ? "カジュアル" : "丁寧")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.top, 6)
                    }
                    Button { accept(index) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 22)
                            Text(suggestion.text).foregroundStyle(.primary)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.system(size: 15)).padding(8).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
              }.padding(4)
              }.frame(height: min(300, CGFloat(suggestions.count) * 64 + CGFloat(Set(suggestions.map(\.register)).count) * 22 + 8))
            }.background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
