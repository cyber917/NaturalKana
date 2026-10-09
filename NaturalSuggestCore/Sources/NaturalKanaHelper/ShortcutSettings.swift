#if os(macOS)
import AppKit
import SwiftUI
import NaturalSuggestCore

@MainActor final class ShortcutSettings {
    private var window: NSWindow?
    func show(check: HelperShortcut, select: HelperShortcut, save: @escaping (HelperShortcut, HelperShortcut) -> String?) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 530, height: 260),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = UIText.t("快捷键")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ShortcutSettingsView(check: check, select: select, save: save))
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

private struct ShortcutSettingsView: View {
    @State var check: HelperShortcut
    @State var select: HelperShortcut
    let save: (HelperShortcut, HelperShortcut) -> String?
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            row(UIText.t("检查当前句子"), shortcut: $check)
            row(UIText.t("全选输入框并检查"), shortcut: $select)
            Text(UIText.t("请先把光标放进输入框。全选检查会选中全部文字；一次限一行、200 字以内。"))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(UIText.t("恢复默认快捷键")) { check = .check; select = .selectAndCheck; message = "" }
                Spacer()
                Button(UIText.t("保存设置")) { message = save(check, select) ?? UIText.t("快捷键已保存，立即生效。") }
                    .keyboardShortcut(.defaultAction)
            }
            Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
        }.padding(20).frame(width: 510)
    }
    private func row(_ title: String, shortcut: Binding<HelperShortcut>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            HStack {
                ForEach([("Control",HelperShortcut.control),("Option",HelperShortcut.option),("Shift",HelperShortcut.shift),("Command",HelperShortcut.command)], id: \.0) { label, mask in
                    Toggle(label, isOn: Binding(get: { shortcut.wrappedValue.modifiers & mask != 0 }, set: { enabled in
                        if enabled { shortcut.wrappedValue.modifiers |= mask } else { shortcut.wrappedValue.modifiers &= ~mask }
                    })).toggleStyle(.checkbox)
                }
                Picker("", selection: shortcut.keyCode) {
                    ForEach(HelperShortcut.keys, id: \.code) { key in Text(key.label).tag(key.code) }
                }.labelsHidden().frame(width: 65)
            }
        }
    }
}
#endif
