import SwiftUI
import NaturalSuggestCore

public struct NaturalSettingsView: View {
    @ObservedObject private var model: SuggestionModel
    @State private var providerKeys: [ProviderKind: String] = [:]
    public init(model: SuggestionModel) { self.model = model }
    private func save() -> Bool {
        guard model.save(providerKeys: providerKeys) else { return false }
        providerKeys = [:]; return true
    }
    private func configuration(_ kind: ProviderKind) -> Binding<ProviderConfiguration> {
        Binding(get: { model.settings.configuration(for: kind) }, set: { model.settings.setConfiguration($0, for: kind) })
    }
    private func key(_ kind: ProviderKind) -> Binding<String> {
        Binding(get: { providerKeys[kind] ?? "" }, set: { providerKeys[kind] = $0 })
    }
    @ViewBuilder private func providerFields(_ kind: ProviderKind) -> some View {
        let config = configuration(kind)
        TextField(UIText.t("接口地址"), text: config.baseURL)
        if config.wrappedValue.baseURL.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("http://") {
            Text(UIText.t("HTTP 不加密：草稿和密钥会以明文发送，只适合本机或可信局域网中的模型服务。公网地址请使用 HTTPS。"))
                .font(.caption).foregroundStyle(.orange)
        }
        TextField(UIText.t("API 模型 ID"), text: config.fastModel)
        SecureField(UIText.t("%@ 密钥（留空保留）", "\(kind.title)"), text: key(kind))
        if kind == .qwen { Toggle(UIText.t("非思考模式"), isOn: config.disableThinking) }
        if model.settings.qualityMode { TextField(UIText.t("评选模型 ID（留空使用上面的模型）"), text: config.qualityModel) }
        DisclosureGroup(UIText.t("接口兼容")) {
            Picker(UIText.t("协议"), selection: config.apiProtocol) {
                Text(UIText.t("OpenAI 兼容")).tag(ProviderProtocol.chatCompletions)
                Text("Claude Messages").tag(ProviderProtocol.anthropicMessages)
            }
            if config.wrappedValue.apiProtocol == .chatCompletions {
                Picker(UIText.t("JSON 格式"), selection: config.responseMode) {
                    Text(UIText.t("自动")).tag(JSONResponseMode.automatic)
                    Text("JSON Schema").tag(JSONResponseMode.schema)
                    Text("JSON Object").tag(JSONResponseMode.object)
                    Text(UIText.t("仅提示词")).tag(JSONResponseMode.prompt)
                }
                Picker(UIText.t("输出长度参数"), selection: config.tokenParameter) {
                    Text(UIText.t("自动")).tag(TokenParameter.automatic)
                    Text("max_tokens").tag(TokenParameter.maxTokens)
                    Text("max_completion_tokens").tag(TokenParameter.maxCompletionTokens)
                }
            }
            Toggle(UIText.t("设置随机度"), isOn: Binding(get: { config.wrappedValue.temperature != nil }, set: { config.wrappedValue.temperature = $0 ? 0.3 : nil }))
            if config.wrappedValue.temperature != nil {
                Slider(value: Binding(get: { config.wrappedValue.temperature ?? 0.3 }, set: { config.wrappedValue.temperature = $0 }), in: 0...1)
            }
        }
    }
    /// Languages the NaturalKana keyboard or input method can type itself.
    private func typedByNaturalKana(_ language: SuggestionLanguage) -> Bool {
        #if os(iOS)
        if model.settings.koreanKeyboard, language.rawValue == "korean" { return true }
        #endif
        return SuggestionLanguage.inputMethodLanguages.contains(language)
    }
    public var body: some View {
        Form {
            Section {
                // Applies and is stored immediately, so a user who cannot read the current language is never stuck.
                Picker(UIText.t("界面语言"), selection: $model.settings.interfaceLanguage) {
                    ForEach(InterfaceLanguage.allCases, id: \.self) { language in Text(language.title).tag(language) }
                }
            }
            Section {
                Toggle(UIText.t("允许发送当前句子"), isOn: $model.settings.consent)
                Toggle(UIText.t("表达建议"), isOn: $model.settings.enabled).disabled(!model.settings.consent)
            } footer: {
                Text(UIText.t("最多发送当前句子 200 字及命中的词库参考。iPhone 需允许键盘完全访问。"))
            }
            Section(UIText.t("服务")) {
                Picker(UIText.t("服务商"), selection: $model.settings.provider) {
                    ForEach(ProviderKind.allCases, id: \.self) { kind in Text(kind.title).tag(kind) }
                }
                providerFields(model.settings.provider)
                if model.settings.qualityMode {
                    Picker(UIText.t("对比服务商"), selection: Binding(get: { model.settings.comparisonProvider }, set: { model.settings.qualityPartner = $0 })) {
                        ForEach(ProviderKind.allCases.filter { $0 != model.settings.provider }, id: \.self) { kind in Text(kind.title).tag(kind) }
                    }
                    DisclosureGroup(model.settings.comparisonProvider.title) { providerFields(model.settings.comparisonProvider) }
                }
            }
            Section(UIText.t("表达")) {
                Picker(UIText.t("建议语言"), selection: Binding(get: { model.settings.autoLanguage ? "auto" : model.settings.language.rawValue }, set: { value in
                    model.settings.autoLanguage = value == "auto"
                    if let language = SuggestionLanguage(rawValue: value) { model.settings.language = language }
                })) {
                    Text(UIText.t("自动")).tag("auto")
                    ForEach(SuggestionLanguage.available, id: \.self) { language in Text(language.title).tag(language.rawValue) }
                }
                if model.settings.autoLanguage {
                    Picker(UIText.t("主要语言"), selection: $model.settings.language) {
                        ForEach(SuggestionLanguage.available, id: \.self) { language in Text(language.title).tag(language) }
                    }
                    Text(UIText.t("按每一句自动判断是哪种语言；分不清时（例如只有汉字的短句）按主要语言处理。")).font(.caption).foregroundStyle(.secondary)
                }
                // NaturalKana itself only types Japanese and English; other languages are typed with another keyboard or IME.
                if !typedByNaturalKana(model.settings.language) || model.settings.autoLanguage {
                    #if os(macOS)
                    Text(UIText.t("日语、英语以外的句子请用菜单栏小助手检查：用任何输入法打完一句，按 ⌃⌥J。")).font(.caption).foregroundStyle(.secondary)
                    #else
                    Text(UIText.t("日语、英语以外的句子：用系统自带的键盘打完一句后，切换到 NaturalKana 键盘即可看到建议。")).font(.caption).foregroundStyle(.secondary)
                    #endif
                }
                #if os(iOS)
                Toggle(UIText.t("键盘加入韩语布局"), isOn: $model.settings.koreanKeyboard)
                if model.settings.koreanKeyboard {
                    Text(UIText.t("保存后，在英文键盘上点左下角的语言键（A／한）切换到韩语。长按 ㅂㅈㄷㄱㅅ 输入 ㅃㅉㄸㄲㅆ，长按 ㅐㅔ 输入 ㅒㅖ。")).font(.caption).foregroundStyle(.secondary)
                }
                #endif
                Picker(UIText.t("语体"), selection: $model.settings.registerPreference) {
                    Text(UIText.t("口语")).tag(RegisterPreference.friendsCasual)
                    Text(model.settings.language == .japanese ? UIText.t("敬语") : UIText.t("礼貌")).tag(RegisterPreference.politeCasual)
                    Text(UIText.t("两种")).tag(RegisterPreference.both)
                }
                Picker(UIText.t("网络用语"), selection: $model.settings.slangLevel) {
                    Text(UIText.t("关闭")).tag(SlangLevel.off); Text(UIText.t("轻度")).tag(SlangLevel.light); Text(UIText.t("流行")).tag(SlangLevel.trendy)
                }
                if model.settings.language == .japanese || model.settings.autoLanguage {
                    Picker(UIText.t("方言"), selection: $model.settings.dialect) {
                        ForEach(Dialect.allCases, id: \.self) { dialect in Text(dialect.title).tag(dialect) }
                    }
                }
                Toggle(UIText.t("标出改动"), isOn: $model.settings.highlightChanges)
                Stepper(UIText.t("建议上限：%@ 条", "\(model.settings.suggestionLimit)"), value: $model.settings.maximumSuggestions, in: SuggestionSettings.suggestionCountRange)
                Stepper(UIText.t("停顿：%@ 毫秒", "\(model.settings.debounceMilliseconds)"), value: $model.settings.debounceMilliseconds, in: 100...2000, step: 100)
            }
            Section {
                DisclosureGroup(UIText.t("高级设置")) {
                    Button(UIText.t("使用快速设置")) { model.useResponsiveSettings() }
                    Stepper(UIText.t("最少字符：%@", "\(model.settings.minimumLength)"), value: $model.settings.minimumLength, in: 1...30)
                    Stepper(UIText.t("每日请求上限：%@", "\(model.settings.dailyCap)"), value: $model.settings.dailyCap, in: 0...10000, step: 50)
                    Text(UIText.t("0 表示不限。请求仍按服务商规则计费。")).font(.caption).foregroundStyle(.secondary)
                    Toggle(UIText.t("双模型评选"), isOn: $model.settings.qualityMode)
                    Text(UIText.t("同时发送给两家服务商，每次最多 3 个请求。")).font(.caption).foregroundStyle(.secondary)
                    #if os(macOS)
                    TextField(UIText.t("禁用应用 Bundle ID"), text: Binding(get: { model.settings.blockedApps.joined(separator: ",") }, set: { model.settings.blockedApps = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }))
                    TextField(UIText.t("第一个候选：Control +"), text: Binding(get: { model.settings.acceptKeys.first ?? "1" }, set: { model.settings.acceptKeys[0] = String($0.prefix(1)) }))
                    TextField(UIText.t("第二个候选：Control +"), text: Binding(get: { model.settings.acceptKeys.count > 1 ? model.settings.acceptKeys[1] : "2" }, set: { model.settings.acceptKeys[1] = String($0.prefix(1)) }))
                    #endif
                    #if os(iOS)
                    Button(UIText.t("检查共享权限")) { model.refreshSharingDiagnostics() }
                    if !model.sharingMessage.isEmpty { Text(model.sharingMessage).font(.caption).foregroundStyle(.secondary) }
                    #endif
                    Button(UIText.t("删除当前服务商密钥"), role: .destructive) { model.deleteKey(model.settings.provider) }
                }
            }
            Section {
                Button(UIText.t("保存设置")) { _ = save() }.buttonStyle(.borderedProminent)
                Button(UIText.t("测试连接")) {
                    if save() { model.testSuggestion() }
                }.disabled(!model.settings.enabled || !model.settings.consent || model.status == .requesting)
                if !model.settingsMessage.isEmpty { Text(model.settingsMessage).font(.caption).foregroundStyle(.secondary) }
                Text(model.statusText).font(.caption).foregroundStyle(.secondary)
                if !model.timingText.isEmpty { Text(model.timingText).font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(model.suggestions.enumerated()), id: \.offset) { _, item in HighlightedSuggestion.text(item.text, original: model.suggestionDraft, enabled: model.settings.highlightChanges).textSelection(.enabled) }
            } footer: {
                Text(UIText.t("密钥保存在设备钥匙串。测试连接会发送一条固定例句。"))
            }
        }.formStyle(.grouped).onAppear { model.reload() }
    }
}
