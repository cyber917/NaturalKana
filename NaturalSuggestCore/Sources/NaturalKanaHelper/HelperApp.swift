#if os(macOS)
import AppKit
import Carbon
import Combine
import ServiceManagement
import SwiftUI
import NaturalSuggestCore
import NaturalSuggestUI

/// Menu-bar helper: press ⌃⌥J in any app, with any input method, to check the sentence at the cursor.
/// It shares settings and the daily budget with the NaturalKana input method through the app group.
@MainActor final class HelperApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let shortcut = "⌃⌥J"
    private let model = SuggestionModel()
    private var statusItem: NSStatusItem?
    private var hotkey: GlobalHotkey?
    private let panel = HelperPanel()
    private var session: Session?
    private var changes: AnyCancellable?

    /// Where the checked sentence came from, which decides how a suggestion is put back.
    private enum Source {
        case field(FocusedField, NSRange)   // read and replaced through Accessibility
        case selection(FocusedField?)        // selected text only; replaced by typing over the selection
        case copied                          // copied with ⌘C; replaced by pasting over the selection
    }
    private struct Session {
        let app: NSRunningApplication?
        let source: Source
        let snapshot: DraftSnapshot
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unlike the input method, the helper can read text typed with any IME, so it checks Chinese too.
        model.languages = SuggestionLanguage.allCases
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "NaturalKana")
        let menu = NSMenu(); menu.delegate = self; item.menu = menu
        statusItem = item
        hotkey = GlobalHotkey(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            Task { await self?.check() }
        }
        changes = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.panel.fit() }
        }
        if !AXIsProcessTrusted() { requestAccessibility() }
    }

    // MARK: - Menu (rebuilt each time so it follows the interface language)

    func menuNeedsUpdate(_ menu: NSMenu) {
        model.reload()
        menu.removeAllItems()
        let check = NSMenuItem(title: UIText.t("检查当前句子"), action: #selector(checkFromMenu), keyEquivalent: "j")
        check.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(check)
        if hotkey == nil {
            menu.addItem(.init(title: UIText.t("快捷键 %@ 被其他软件占用了，只能从这里检查。", Self.shortcut), action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        if !AXIsProcessTrusted() {
            menu.addItem(.init(title: UIText.t("允许“辅助功能”权限…"), action: #selector(requestAccessibility), keyEquivalent: ""))
        }
        menu.addItem(.init(title: UIText.t("设置…"), action: #selector(openSettings), keyEquivalent: ","))
        let login = NSMenuItem(title: UIText.t("登录时自动启动"), action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.init(title: UIText.t("使用说明"), action: #selector(openHelp), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(.init(title: UIText.t("退出"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
    }
    @objc private func checkFromMenu() { Task { await check() } }
    @objc private func requestAccessibility() {
        // Shows the system prompt that leads to System Settings > Privacy & Security > Accessibility.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
    /// The settings live in the input method; reopening it shows its settings window.
    @objc private func openSettings() {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "NaturalKanaInputMethodBundleID") as? String,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            panel.show(notice: UIText.t("没有找到 NaturalKana 输入法，请先安装输入法。"), near: nil); return
        }
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
        Task {
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            guard !running else { return }
            // A freshly launched input method only shows its settings when reopened.
            try? await Task.sleep(for: .seconds(1.5))
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { panel.show(notice: UIText.t("无法更改登录项，请在“系统设置 → 通用 → 登录项”里手动添加。"), near: nil) }
    }
    @objc private func openHelp() {
        if let url = URL(string: "https://github.com/cyber917/NaturalKana/blob/main/docs/USAGE.md#mac-菜单栏小助手") { NSWorkspace.shared.open(url) }
    }

    // MARK: - Checking

    func check() async {
        panel.close(); session = nil; model.invalidate()
        guard AXIsProcessTrusted() else {
            requestAccessibility()
            panel.show(notice: UIText.t("请先在“系统设置 → 隐私与安全性 → 辅助功能”里允许 NaturalKana Helper，再按 %@。", Self.shortcut), near: nil)
            return
        }
        let app = NSWorkspace.shared.frontmostApplication
        let field = FocusedField.current()
        if field?.isSecure == true || IsSecureEventInputEnabled() {
            panel.show(notice: UIText.t("这是密码输入框，不会检查。"), near: nil); return
        }
        let text: String, source: Source
        var anchor: NSRect?
        if let field, let value = field.value, let selection = field.selectedRange {
            switch FieldDraft.make(value: value, selection: selection) {
            case .success(let draft):
                text = draft.text; source = .field(field, draft.range); anchor = field.bounds(for: draft.range)
            case .failure(let problem):
                panel.show(notice: Self.message(problem), near: field.bounds(for: selection)); return
            }
        } else if let field, let selected = field.selectedText, !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = selected; source = .selection(field); anchor = field.selectedRange.flatMap(field.bounds(for:)) ?? field.frame
        } else if let copied = await Keystrokes.copySelection(), !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = copied; source = .copied; anchor = field?.frame
        } else {
            panel.show(notice: UIText.t("这个 App 不提供输入框里的文字。请先选中要检查的那一句，再按 %@。", Self.shortcut), near: field?.frame); return
        }
        guard !text.contains(where: \.isNewline) else { panel.show(notice: Self.message(.multiline), near: anchor); return }
        guard text.count <= 200 else { panel.show(notice: Self.message(.tooLong), near: anchor); return }
        let snapshot = DraftSnapshot(text: text, fieldID: "helper-" + UUID().uuidString, appID: app?.bundleIdentifier ?? "")
        session = Session(app: app, source: source, snapshot: snapshot)
        panel.show(model: model, original: text, near: anchor, accept: { [weak self] index in Task { await self?.accept(index) } },
                   dismiss: { [weak self] in self?.dismiss() })
        model.update(snapshot, explicit: true)
    }

    private static func message(_ problem: FieldDraft.Problem) -> String {
        switch problem {
        case .empty: UIText.t("光标所在的这一行是空的。")
        case .multiline: UIText.t("一次只能检查一句话，请只选中一行。")
        case .tooLong: UIText.t("这一行超过 200 字。请选中要检查的那一句，再按 %@。", shortcut)
        }
    }

    private func dismiss() {
        panel.close(); model.dismiss()
        session?.app?.activate()
        session = nil
    }

    private func accept(_ index: Int) async {
        guard let session, let text = model.accept(index, snapshot: session.snapshot) else { dismiss(); return }
        self.session = nil
        panel.close()
        let original = session.snapshot.text
        switch session.source {
        case .field(let field, let range):
            // Never replace when the field changed while the suggestions were being generated.
            guard let value = field.value, NSMaxRange(range) <= value.utf16.count, (value as NSString).substring(with: range) == original else {
                copyInstead(text, UIText.t("原句已经变了，建议已复制，请手动粘贴。")); return
            }
            session.app?.activate()
            if field.replace(range, with: text) { return }
            // Some apps expose their text but refuse edits through Accessibility: select it and paste.
            guard field.select(range) else { copyInstead(text, UIText.t("此应用不支持这段文字的安全替换；建议已复制，请选中原句后粘贴")); return }
            await Keystrokes.paste(text)
        case .selection(let field):
            session.app?.activate()
            guard field?.selectedText == original else { copyInstead(text, UIText.t("原句已经变了，建议已复制，请手动粘贴。")); return }
            try? await Task.sleep(for: .milliseconds(80))
            await Keystrokes.paste(text)
        case .copied:
            // The selection is still in place after ⌘C.
            session.app?.activate()
            try? await Task.sleep(for: .milliseconds(80))
            await Keystrokes.paste(text)
        }
    }

    private func copyInstead(_ text: String, _ notice: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        panel.show(notice: notice, near: nil)
    }
}

/// A panel that takes keys (numbers, Esc) without activating the helper, so the target app stays frontmost.
@MainActor final class HelperPanel {
    private final class KeyPanel: NSPanel {
        var onKey: ((NSEvent) -> Bool)?
        var onCancel: (() -> Void)?
        override var canBecomeKey: Bool { true }
        override func keyDown(with event: NSEvent) { if onKey?(event) != true { super.keyDown(with: event) } }
        // Esc arrives here when the SwiftUI content does not handle it.
        override func cancelOperation(_ sender: Any?) { onCancel?() }
    }
    private let window: KeyPanel = {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true; panel.level = .popUpMenu; panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary, .moveToActiveSpace]
        return panel
    }()
    private var anchor: NSRect?
    private var hideTask: Task<Void, Never>?

    func show(model: SuggestionModel, original: String, near anchor: NSRect?, accept: @escaping (Int) -> Void, dismiss: @escaping () -> Void) {
        hideTask?.cancel()
        window.onCancel = dismiss
        window.onKey = { event in
            if event.keyCode == UInt16(kVK_Escape) { dismiss(); return true }
            if let digit = event.charactersIgnoringModifiers.flatMap(Int.init), (1...9).contains(digit), digit <= model.suggestions.count {
                accept(digit - 1); return true
            }
            return false
        }
        present(HelperPanelView(model: model, original: original, accept: accept, dismiss: dismiss), near: anchor)
    }
    /// A short message that closes by itself.
    func show(notice: String, near anchor: NSRect?) {
        hideTask?.cancel()
        window.onCancel = { [weak self] in self?.close() }
        window.onKey = { [weak self] _ in self?.close(); return true }
        present(NoticeView(text: notice), near: anchor)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { self?.close() }
        }
    }
    func close() { hideTask?.cancel(); window.orderOut(nil) }

    private func present(_ view: some View, near anchor: NSRect?) {
        self.anchor = anchor ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        window.contentView = NSHostingView(rootView: view)
        fit()
        window.makeKeyAndOrderFront(nil)
    }
    /// Keeps the panel just below the sentence (above it near the bottom of the screen) as its content changes.
    func fit() {
        guard let content = window.contentView, let anchor else { return }
        let size = content.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor.insetBy(dx: -1, dy: -1)) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = min(max(anchor.minX, screen.minX), screen.maxX - size.width)
        let below = anchor.minY - size.height - 6
        let y = below >= screen.minY ? below : min(anchor.maxY + 6, screen.maxY - size.height)
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}

private struct HelperPanelView: View {
    @ObservedObject var model: SuggestionModel
    let original: String
    let accept: (Int) -> Void
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.suggestions.isEmpty {
                HStack(spacing: 8) {
                    SuggestionStatusIndicator(status: model.status == .idle ? .requesting : model.status)
                    Text(model.status == .idle || model.status == .waiting ? UIText.t("正在获取建议…") : model.status.message)
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain)
                        .accessibilityLabel(UIText.t("关闭提示"))
                }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            } else {
                SuggestionStrip(suggestions: model.suggestions, language: model.suggestionLanguage, original: original,
                                highlightChanges: model.settings.highlightChanges, dismiss: dismiss, accept: accept)
                Text(UIText.t("按数字键或点击采用 · Esc 关闭")).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
            }
        }.frame(width: 480)
    }
}

private struct NoticeView: View {
    let text: String
    var body: some View {
        Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            .padding(12).frame(width: 360, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
#endif
