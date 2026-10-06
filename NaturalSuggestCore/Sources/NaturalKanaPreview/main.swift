import SwiftUI
import NaturalSuggestCore
import NaturalSuggestUI

@main struct NaturalKanaPreviewApp: App {
    @StateObject private var model = SuggestionModel()
    var body: some Scene {
        WindowGroup("NaturalKana · 开发预览") { PreviewView(model: model).frame(minWidth: 720, minHeight: 680) }
    }
}
struct PreviewView: View {
    @ObservedObject var model: SuggestionModel
    @State private var draft = ""
    private var snapshot: DraftSnapshot { .init(text: DraftSnapshot.currentLine(before: draft, after: ""), fieldID: "preview") }
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 18) {
                Text("NaturalKana").font(.largeTitle.bold())
                Text("日语自然表达 · 开发预览").foregroundStyle(.secondary)
                Text("这是独立测试窗口。系统输入法与 iOS 键盘尚需 Xcode 构建和设备验证。")
                    .font(.callout).foregroundStyle(.secondary)
                TextEditor(text: $draft).font(.title3).frame(height: 180).border(.quaternary)
                    .onChange(of: draft) { _ in model.update(snapshot) }
                SuggestionStrip(suggestions: model.suggestions) { index in
                    let current = snapshot
                    if let replacement = model.accept(index, snapshot: current), draft.hasSuffix(current.text) {
                        draft = String(draft.dropLast(current.text.count)) + replacement
                    }
                }
                Button("获取建议") { model.update(snapshot, explicit: true) }
                    .disabled(model.status == .requesting)
                Text(model.statusText).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(24).frame(minWidth: 300)
            NaturalSettingsView(model: model).frame(minWidth: 380)
        }.onDisappear { model.cancel() }
    }
}
