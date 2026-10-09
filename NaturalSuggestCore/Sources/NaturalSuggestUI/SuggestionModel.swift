import SwiftUI
import NaturalKanaStorage
import NaturalSuggestCore

@MainActor public final class SuggestionModel: ObservableObject {
    @Published public var settings: SuggestionSettings {
        didSet {
            UIText.language = settings.interfaceLanguage
            if settings.interfaceLanguage != oldValue.interfaceLanguage || settings.extraKeyboardLayouts != oldValue.extraKeyboardLayouts
                || settings.keyboardSwitchOrder != oldValue.keyboardSwitchOrder || settings.keyboardWordLearning != oldValue.keyboardWordLearning {
                storeImmediateSettings()
            }
        }
    }
    /// Language of the shown suggestions: the detected one when auto language is on.
    @Published public private(set) var suggestionLanguage: SuggestionLanguage = .japanese
    /// Languages this host can check (the Mac input method cannot see Chinese typed with another IME).
    public var languages: [SuggestionLanguage] {
        get { engine?.languages ?? SuggestionLanguage.available }
        set { engine?.languages = newValue }
    }
    @Published public private(set) var suggestions: [Suggestion] = []
    @Published public private(set) var status: Diagnostics = .idle
    @Published public var settingsMessage = ""
    @Published public private(set) var personalEntries: [PersonalLexiconEntry] = []
    @Published public private(set) var timingText = ""
    @Published public private(set) var suggestionDraft = ""
    private var personalData: Data?
    public var onStatusChange: ((Diagnostics) -> Void)?
    @Published public private(set) var sharingMessage = ""
    private let defaults: UserDefaults?
    private var keychain: KeychainStore {
        get throws {
            #if os(iOS)
            return KeychainStore(accessGroup: try SharedKeychain.accessGroup())
            #else
            return KeychainStore(accessGroup: Bundle.main.object(forInfoDictionaryKey: "NaturalKanaKeychainGroup") as? String)
            #endif
        }
    }
    private let engine: SuggestionEngine?
    public init() {
        #if os(iOS)
        let storage = try? SharedContainer.current.get().defaults
        #else
        let group = Bundle.main.object(forInfoDictionaryKey: "NaturalKanaAppGroup") as? String
        let storage: UserDefaults? = group.flatMap(UserDefaults.init(suiteName:)) ?? UserDefaults(suiteName: "NaturalKana")!
        if group != nil, let storage { Self.migrateLegacyDefaults(to: storage) }
        #endif
        defaults = storage
        settings = defaults?.data(forKey: "nk.settings").flatMap { try? JSONDecoder().decode(SuggestionSettings.self, from: $0) } ?? SuggestionSettings()
        engine = storage.flatMap { store in (try? PromptBuilder()).map { SuggestionEngine(budget: DailyBudget(defaults: store), prompt: $0) } }
        UIText.language = settings.interfaceLanguage
        suggestionLanguage = settings.language
        engine?.onChange = { [weak self] items, state in
            guard let self else { return }
            suggestionLanguage = engine?.language ?? settings.language
            suggestions = items; status = state
            suggestionDraft = engine?.suggestionDraft ?? ""
            timingText = engine?.cacheHit == true ? UIText.t("缓存命中，无需联网") : engine?.requestSeconds.map { String(format: UIText.t("本次联网耗时 %.2f 秒"), $0) } ?? ""
            onStatusChange?(state)
        }
        reloadPersonalLexicon()
    }
    #if os(macOS)
    /// Earlier Mac builds kept settings in the input method's private "NaturalKana" suite. They move to the
    /// app group once, so the menu-bar helper shares them. Keys already in the group are never overwritten.
    static func migrateLegacyDefaults(from legacy: UserDefaults? = UserDefaults(suiteName: "NaturalKana"), to group: UserDefaults) {
        guard group.object(forKey: "nk.settings") == nil, let legacy, legacy.object(forKey: "nk.settings") != nil else { return }
        for key in ["nk.settings", "nk.personalLexicon", "nk.budget.day", "nk.budget.used"] {
            if let value = legacy.object(forKey: key) { group.set(value, forKey: key) }
        }
    }
    #endif
    private func reloadPersonalLexicon() {
        let data = defaults?.data(forKey: "nk.personalLexicon")
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
        guard let defaults else { throw SharingFailure.defaultsUnavailable }
        defaults.set(data, forKey: "nk.personalLexicon")
        personalData = data; personalEntries = entries; engine?.setPersonalLexicon(entries)
    }
    public func clearKeyboardWordMemory() {
        if let defaults { WordCompletionMemory.clear(in: defaults) }
    }

    public func useResponsiveSettings() {
        settings.debounceMilliseconds = 300; settings.qualityMode = false
        if settings.provider == .qwen { settings.qwen.disableThinking = true }
    }
    public func reload() {
        reloadPersonalLexicon()
        #if os(iOS)
        recordKeyboardSharingCheck()
        #endif
        if let data = defaults?.data(forKey: "nk.settings"), let new = try? JSONDecoder().decode(SuggestionSettings.self, from: data), new != settings {
            engine?.cancel(clearCache: true); settings = new
        }
    }
    @discardableResult public func save(openAIKey: String = "", qwenKey: String = "", providerKeys: [ProviderKind: String] = [:]) -> Bool {
        do {
            guard let defaults else { throw SharingFailure.defaultsUnavailable }
            if !openAIKey.isEmpty { try keychain.write(openAIKey, account: ProviderKind.openAI.rawValue) }
            if !qwenKey.isEmpty { try keychain.write(qwenKey, account: ProviderKind.qwen.rawValue) }
            for (kind, key) in providerKeys where !key.isEmpty { try keychain.write(key, account: kind.rawValue) }
            defaults.set(try JSONEncoder().encode(settings), forKey: "nk.settings")
            engine?.cancel(clearCache: true); settingsMessage = UIText.t("已保存。密钥保存在系统钥匙串。")
            return true
        } catch { settingsMessage = Self.sharingError(error); return false }
    }
    /// Interface language and keyboard choices take effect at once; other unsaved edits still wait for “保存设置”.
    private func storeImmediateSettings() {
        guard let defaults else { return }
        var stored = defaults.data(forKey: "nk.settings").flatMap { try? JSONDecoder().decode(SuggestionSettings.self, from: $0) } ?? SuggestionSettings()
        stored.interfaceLanguage = settings.interfaceLanguage
        stored.extraKeyboardLayouts = settings.extraKeyboardLayouts
        stored.keyboardSwitchOrder = settings.keyboardSwitchOrder
        stored.keyboardWordLearning = settings.keyboardWordLearning
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: "nk.settings") }
    }
    public func testSuggestion() {
        update(DraftSnapshot(text: settings.language.testDraft, fieldID: "settings-test"), explicit: true)
    }
    public func deleteKey(_ kind: ProviderKind) {
        do { try keychain.write("", account: kind.rawValue); engine?.cancel(clearCache: true); settingsMessage = UIText.t("密钥已删除。") }
        catch { settingsMessage = UIText.t("无法删除密钥。") }
    }
    public func cancel() { engine?.cancel(clearCache: true) }
    public func invalidate() { engine?.cancel() }
    public func dismiss() { engine?.dismiss() }
    public func reportHostLimitation(fullAccess: Bool) {
        engine?.cancel()
        status = fullAccess ? .contextUnavailable : .requiresFullAccess
        onStatusChange?(status)
    }
    public func update(_ snapshot: DraftSnapshot, explicit: Bool = false) {
        reload()
        #if os(iOS)
        do { _ = try keychain }
        catch { settingsMessage = Self.sharingError(error); status = .unavailable; onStatusChange?(status); return }
        #endif
        func client(_ kind: ProviderKind) -> CompatibleProvider {
            CompatibleProvider(kind: kind, configuration: settings.configuration(for: kind), key: (try? keychain.read(kind.rawValue)) ?? "")
        }
        let provider: any SuggestionProvider
        if settings.qualityMode { provider = QualityProvider(first: client(settings.provider), second: client(settings.comparisonProvider), judge: client(settings.provider)) }
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
    private static func sharingError(_ error: any Error) -> String {
        if let error = error as? SharingFailure { return error.message }
        if let error = error as? KeychainFailure { return UIText.t("钥匙串不可用（%@）。请检查共享权限。", "\(error.status)") }
        return UIText.t("共享设置不可用，请检查签名。")
    }
    #if os(iOS)
    /// Non-secret challenge verifies app -> keyboard settings AND explicit-group Keychain.
    /// No API key is put in defaults or displayed by diagnostics.
    public func refreshSharingDiagnostics() {
        guard let defaults else { sharingMessage = SharedContainer.failure?.message ?? UIText.t("共享设置不可用（G04）"); return }
        do {
            let store = try keychain
            let marker = KeychainStore(service: "NaturalKana.sharing-check", accessGroup: store.accessGroup)
            let nonce: String
            if let existing = defaults.string(forKey: "nk.check.app") { nonce = existing }
            else {
                nonce = UUID().uuidString
                try marker.write(nonce, account: "challenge")
                defaults.set(nonce, forKey: "nk.check.app")
            }
            let code = store.availability(settings.provider.rawValue)
            let keyState = code == 0 ? UIText.t("可读") : code == -25300 ? UIText.t("未保存") : UIText.t("错误 %@", "\(code)")
            let confirmed = defaults.string(forKey: "nk.check.keyboard") == nonce
            let keyboard = confirmed ? (defaults.bool(forKey: "nk.check.keychain") ? UIText.t("配置、钥匙串共享通过") : UIText.t("钥匙串校验失败（%@）", "\(defaults.integer(forKey: "nk.check.code"))")) : UIText.t("等待验证，请切换到键盘后返回")
            sharingMessage = UIText.t("主应用：共享配置可读，密钥%@。键盘：%@。", "\(keyState)", "\(keyboard)")
        } catch { sharingMessage = Self.sharingError(error) }
    }
    private func recordKeyboardSharingCheck() {
        guard Bundle.main.bundleURL.pathExtension == "appex", let defaults,
              let nonce = defaults.string(forKey: "nk.check.app"),
              defaults.string(forKey: "nk.check.keyboard") != nonce else { return }
        do {
            let marker = KeychainStore(service: "NaturalKana.sharing-check", accessGroup: try keychain.accessGroup)
            defaults.set(try marker.read("challenge") == nonce, forKey: "nk.check.keychain")
            defaults.set(0, forKey: "nk.check.code")
            defaults.set(nonce, forKey: "nk.check.keyboard")
        } catch {
            sharingMessage = Self.sharingError(error)
            defaults.set(false, forKey: "nk.check.keychain")
            let code: Int32
            if let failure = error as? KeychainFailure { code = failure.status }
            else if case .keychain(let status) = error as? SharingFailure { code = status }
            else { code = -1 }
            defaults.set(code, forKey: "nk.check.code")
            defaults.set(nonce, forKey: "nk.check.keyboard")
        }
    }
    #endif
    public var statusText: String { status.message }
    public var receivedCandidateCount: Int? { engine?.receivedCandidateCount }
}
public struct SuggestionStrip: View {
    public let suggestions: [Suggestion]
    public let language: SuggestionLanguage
    public let accept: (Int) -> Void
    public let original: String
    public let highlightChanges: Bool
    public let dismiss: (() -> Void)?
    public let dragHandle: AnyView?
    public init(suggestions: [Suggestion], language: SuggestionLanguage = .japanese, original: String = "", highlightChanges: Bool = true, dragHandle: AnyView? = nil, dismiss: (() -> Void)? = nil, accept: @escaping (Int) -> Void) {
        self.language = language
        self.original = original; self.highlightChanges = highlightChanges
        self.dismiss = dismiss; self.dragHandle = dragHandle
        self.suggestions = suggestions; self.accept = accept
    }
    public var body: some View {
        if !suggestions.isEmpty {
            VStack(spacing: 0) {
              if let dismiss {
                HStack {
                    if let dragHandle { dragHandle }
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary).frame(width: 26, height: 24).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(language.closeTitle + " (Esc)").accessibilityLabel(language.closeTitle)
                }.padding(.horizontal, 4).padding(.top, 2)
              }
              ScrollView(.vertical) {
              VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(suggestions.prefix(SuggestionSettings.suggestionCountRange.upperBound).enumerated()), id: \.offset) { index, suggestion in
                    if index == 0 || suggestions[index - 1].register != suggestion.register {
                        Text(language.registerTitle(suggestion.register))
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.top, 6)
                    }
                    Button { accept(index) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 22)
                            HighlightedSuggestion.text(suggestion.text, original: original, enabled: highlightChanges)
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

public enum HighlightedSuggestion {
    public static func text(_ candidate: String, original: String, enabled: Bool = true) -> Text {
        guard enabled else { return Text(candidate).foregroundColor(.primary) }
        return SuggestionDiff.spans(original: original, candidate: candidate).reduce(Text("")) { text, span in
            text + Text(span.text).foregroundColor(span.changed ? .accentColor : .primary)
        }
    }
}
