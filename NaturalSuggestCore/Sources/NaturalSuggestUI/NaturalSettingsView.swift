import SwiftUI
import NaturalSuggestCore

public struct NaturalSettingsView: View {
    @ObservedObject private var model: SuggestionModel
    @State private var openAIKey = ""
    @State private var qwenKey = ""
    public init(model: SuggestionModel) { self.model = model }
    private func save() -> Bool {
        guard model.save(openAIKey: openAIKey, qwenKey: qwenKey) else { return false }
        openAIKey = ""; qwenKey = ""; return true
    }
    public var body: some View {
        Form {
            Section {
                Toggle("允许发送当前句子", isOn: $model.settings.consent)
                Toggle("日语建议", isOn: $model.settings.enabled).disabled(!model.settings.consent)
            } footer: {
                Text("最多发送当前句子 200 字及命中的词库参考。iPhone 需允许键盘完全访问。")
            }
            Section("服务") {
                Picker("服务商", selection: $model.settings.provider) {
                    Text("OpenAI").tag(ProviderKind.openAI)
                    Text("Qwen / 百炼").tag(ProviderKind.qwen)
                }
                if model.settings.provider == .openAI || model.settings.qualityMode {
                    TextField("OpenAI 接口地址", text: $model.settings.openAI.baseURL)
                    TextField("OpenAI 模型", text: $model.settings.openAI.fastModel)
                    SecureField("OpenAI 密钥（留空保留）", text: $openAIKey)
                    if model.settings.qualityMode { TextField("OpenAI 高质量模型", text: $model.settings.openAI.qualityModel) }
                }
                if model.settings.provider == .qwen || model.settings.qualityMode {
                    TextField("Qwen 接口地址", text: $model.settings.qwen.baseURL)
                    TextField("Qwen 模型", text: $model.settings.qwen.fastModel)
                    SecureField("Qwen 密钥（留空保留）", text: $qwenKey)
                    Toggle("非思考模式", isOn: $model.settings.qwen.disableThinking)
                    if model.settings.qualityMode { TextField("Qwen 高质量模型", text: $model.settings.qwen.qualityModel) }
                }
            }
            Section("表达") {
                Picker("语体", selection: $model.settings.registerPreference) {
                    Text("口语").tag(RegisterPreference.friendsCasual)
                    Text("敬语").tag(RegisterPreference.politeCasual)
                    Text("两种").tag(RegisterPreference.both)
                }
                Picker("网络用语", selection: $model.settings.slangLevel) {
                    Text("关闭").tag(SlangLevel.off); Text("轻度").tag(SlangLevel.light); Text("流行").tag(SlangLevel.trendy)
                }
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
                    Button("删除 OpenAI 密钥", role: .destructive) { model.deleteKey(.openAI) }
                    Button("删除 Qwen 密钥", role: .destructive) { model.deleteKey(.qwen) }
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
                ForEach(Array(model.suggestions.enumerated()), id: \.offset) { _, item in Text(item.text).textSelection(.enabled) }
            } footer: {
                Text("密钥保存在设备钥匙串。测试连接会发送一条固定例句。")
            }
        }.formStyle(.grouped).onAppear { model.reload() }
    }
}
