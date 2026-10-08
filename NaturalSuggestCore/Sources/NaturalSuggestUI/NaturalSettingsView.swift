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
        TextField("接口地址", text: config.baseURL)
        if config.wrappedValue.baseURL.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("http://") {
            Text("HTTP 不加密：草稿和密钥会以明文发送，只适合本机或可信局域网中的模型服务。公网地址请使用 HTTPS。")
                .font(.caption).foregroundStyle(.orange)
        }
        TextField("API 模型 ID", text: config.fastModel)
        SecureField("\(kind.title) 密钥（留空保留）", text: key(kind))
        if kind == .qwen { Toggle("非思考模式", isOn: config.disableThinking) }
        if model.settings.qualityMode { TextField("评选模型 ID（留空使用上面的模型）", text: config.qualityModel) }
        DisclosureGroup("接口兼容") {
            Picker("协议", selection: config.apiProtocol) {
                Text("OpenAI 兼容").tag(ProviderProtocol.chatCompletions)
                Text("Claude Messages").tag(ProviderProtocol.anthropicMessages)
            }
            if config.wrappedValue.apiProtocol == .chatCompletions {
                Picker("JSON 格式", selection: config.responseMode) {
                    Text("自动").tag(JSONResponseMode.automatic)
                    Text("JSON Schema").tag(JSONResponseMode.schema)
                    Text("JSON Object").tag(JSONResponseMode.object)
                    Text("仅提示词").tag(JSONResponseMode.prompt)
                }
                Picker("输出长度参数", selection: config.tokenParameter) {
                    Text("自动").tag(TokenParameter.automatic)
                    Text("max_tokens").tag(TokenParameter.maxTokens)
                    Text("max_completion_tokens").tag(TokenParameter.maxCompletionTokens)
                }
            }
            Toggle("设置随机度", isOn: Binding(get: { config.wrappedValue.temperature != nil }, set: { config.wrappedValue.temperature = $0 ? 0.3 : nil }))
            if config.wrappedValue.temperature != nil {
                Slider(value: Binding(get: { config.wrappedValue.temperature ?? 0.3 }, set: { config.wrappedValue.temperature = $0 }), in: 0...1)
            }
        }
    }
    public var body: some View {
        Form {
            Section {
                Toggle("允许发送当前句子", isOn: $model.settings.consent)
                Toggle("表达建议", isOn: $model.settings.enabled).disabled(!model.settings.consent)
            } footer: {
                Text("最多发送当前句子 200 字及命中的词库参考。iPhone 需允许键盘完全访问。")
            }
            Section("服务") {
                Picker("服务商", selection: $model.settings.provider) {
                    ForEach(ProviderKind.allCases, id: \.self) { kind in Text(kind.title).tag(kind) }
                }
                providerFields(model.settings.provider)
                if model.settings.qualityMode {
                    Picker("对比服务商", selection: Binding(get: { model.settings.comparisonProvider }, set: { model.settings.qualityPartner = $0 })) {
                        ForEach(ProviderKind.allCases.filter { $0 != model.settings.provider }, id: \.self) { kind in Text(kind.title).tag(kind) }
                    }
                    DisclosureGroup(model.settings.comparisonProvider.title) { providerFields(model.settings.comparisonProvider) }
                }
            }
            Section("表达") {
                Picker("建议语言", selection: $model.settings.language) {
                    ForEach(SuggestionLanguage.allCases, id: \.self) { language in Text(language.title).tag(language) }
                }
                Picker("语体", selection: $model.settings.registerPreference) {
                    Text("口语").tag(RegisterPreference.friendsCasual)
                    Text(model.settings.language == .japanese ? "敬语" : "礼貌").tag(RegisterPreference.politeCasual)
                    Text("两种").tag(RegisterPreference.both)
                }
                Picker("网络用语", selection: $model.settings.slangLevel) {
                    Text("关闭").tag(SlangLevel.off); Text("轻度").tag(SlangLevel.light); Text("流行").tag(SlangLevel.trendy)
                }
                Toggle("标出改动", isOn: $model.settings.highlightChanges)
                Stepper("建议上限：\(model.settings.suggestionLimit) 条", value: $model.settings.maximumSuggestions, in: SuggestionSettings.suggestionCountRange)
                Stepper("停顿：\(model.settings.debounceMilliseconds) 毫秒", value: $model.settings.debounceMilliseconds, in: 100...2000, step: 100)
            }
            Section {
                DisclosureGroup("高级设置") {
                    Button("使用快速设置") { model.useResponsiveSettings() }
                    Stepper("最少字符：\(model.settings.minimumLength)", value: $model.settings.minimumLength, in: 1...30)
                    Stepper("每日请求上限：\(model.settings.dailyCap)", value: $model.settings.dailyCap, in: 0...10000, step: 50)
                    Text("0 表示不限。请求仍按服务商规则计费。").font(.caption).foregroundStyle(.secondary)
                    Toggle("双模型评选", isOn: $model.settings.qualityMode)
                    Text("同时发送给两家服务商，每次最多 3 个请求。").font(.caption).foregroundStyle(.secondary)
                    #if os(macOS)
                    TextField("禁用应用 Bundle ID", text: Binding(get: { model.settings.blockedApps.joined(separator: ",") }, set: { model.settings.blockedApps = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }))
                    TextField("第一个候选：Control +", text: Binding(get: { model.settings.acceptKeys.first ?? "1" }, set: { model.settings.acceptKeys[0] = String($0.prefix(1)) }))
                    TextField("第二个候选：Control +", text: Binding(get: { model.settings.acceptKeys.count > 1 ? model.settings.acceptKeys[1] : "2" }, set: { model.settings.acceptKeys[1] = String($0.prefix(1)) }))
                    #endif
                    #if os(iOS)
                    Button("检查共享权限") { model.refreshSharingDiagnostics() }
                    if !model.sharingMessage.isEmpty { Text(model.sharingMessage).font(.caption).foregroundStyle(.secondary) }
                    #endif
                    Button("删除当前服务商密钥", role: .destructive) { model.deleteKey(model.settings.provider) }
                }
            }
            Section {
                Button("保存设置") { _ = save() }.buttonStyle(.borderedProminent)
                Button("测试连接") {
                    if save() { model.testSuggestion() }
                }.disabled(!model.settings.enabled || !model.settings.consent || model.status == .requesting)
                if !model.settingsMessage.isEmpty { Text(model.settingsMessage).font(.caption).foregroundStyle(.secondary) }
                Text(model.statusText).font(.caption).foregroundStyle(.secondary)
                if !model.timingText.isEmpty { Text(model.timingText).font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(model.suggestions.enumerated()), id: \.offset) { _, item in HighlightedSuggestion.text(item.text, original: model.suggestionDraft, enabled: model.settings.highlightChanges).textSelection(.enabled) }
            } footer: {
                Text("密钥保存在设备钥匙串。测试连接会发送一条固定例句。")
            }
        }.formStyle(.grouped).onAppear { model.reload() }
    }
}
