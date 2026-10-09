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
    private var checkShortcut = HelperShortcut.check
    private var selectShortcut = HelperShortcut.selectAndCheck
    private var shortcut: String { checkShortcut.label }
    private let shortcutSettings = ShortcutSettings()
    private var selectHotkey: GlobalHotkey?
    private var operation: Task<Void, Never>?
    private let model = SuggestionModel()
    private var statusItem: NSStatusItem?
    private var hotkey: GlobalHotkey?
    private let panel = HelperPanel()
    private var session: Session?
    private var changes: AnyCancellable?

    /// Where the checked sentence came from, which decides how a suggestion is put back.
    private enum Source {
        case field(FocusedField, NSRange)   // read and replaced through Accessibility
        case selection(FocusedField?, NSRange?)        // selected text only; replaced by typing over the selection
        case copied(FocusedField?)           // copied with ⌘C; replaced by pasting over the selection
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
        if let data = UserDefaults.standard.data(forKey: "helper.checkShortcut"), let value = try? JSONDecoder().decode(HelperShortcut.self, from: data), value.isValid { checkShortcut = value }
        if let data = UserDefaults.standard.data(forKey: "helper.selectShortcut"), let value = try? JSONDecoder().decode(HelperShortcut.self, from: data), value.isValid, value != checkShortcut { selectShortcut = value }
        registerShortcuts()
        changes = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.panel.fit() }
        }
        if !AXIsProcessTrusted() { requestAccessibility() }
        if !UserDefaults.standard.bool(forKey: "helper.shownShortcutSettings") {
            openShortcutSettings()
            UserDefaults.standard.set(true, forKey: "helper.shownShortcutSettings")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openShortcutSettings()
        return true
    }

    // MARK: - Menu (rebuilt each time so it follows the interface language)

    func menuNeedsUpdate(_ menu: NSMenu) {
        model.reload()
        menu.removeAllItems()
        menu.addItem(.init(title: UIText.t("检查当前句子") + "  " + checkShortcut.label, action: #selector(checkFromMenu), keyEquivalent: ""))
        menu.addItem(.init(title: UIText.t("全选输入框并检查") + "  " + selectShortcut.label, action: #selector(selectFromMenu), keyEquivalent: ""))
        if hotkey == nil || selectHotkey == nil {
            menu.addItem(.init(title: UIText.t("快捷键 %@ 被其他软件占用了，只能从这里检查。", hotkey == nil ? checkShortcut.label : selectShortcut.label), action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        if !AXIsProcessTrusted() {
            menu.addItem(.init(title: UIText.t("允许“辅助功能”权限…"), action: #selector(requestAccessibility), keyEquivalent: ""))
        }
        menu.addItem(.init(title: UIText.t("快捷键…"), action: #selector(openShortcutSettings), keyEquivalent: ""))
        menu.addItem(.init(title: UIText.t("设置…"), action: #selector(openSettings), keyEquivalent: ","))
        let login = NSMenuItem(title: UIText.t("登录时自动启动"), action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.init(title: UIText.t("使用说明"), action: #selector(openHelp), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(.init(title: UIText.t("退出"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
    }
    private func runOperation(_ action: @escaping @MainActor () async -> Void) {
        let previous = operation
        previous?.cancel()
        operation = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await action()
        }
    }
    private func startCheck(selectAll: Bool = false) {
        runOperation { [weak self] in await self?.check(selectAll: selectAll) }
    }
    private func registerShortcuts() {
        hotkey = GlobalHotkey(id: 1, keyCode: checkShortcut.keyCode, modifiers: checkShortcut.modifiers) { [weak self] in self?.startCheck() }
        selectHotkey = GlobalHotkey(id: 2, keyCode: selectShortcut.keyCode, modifiers: selectShortcut.modifiers) { [weak self] in self?.startCheck(selectAll: true) }
    }
    private func saveShortcuts(_ check: HelperShortcut, _ select: HelperShortcut) -> String? {
        guard check.isValid, select.isValid else { return UIText.t("请选择字母或数字，并搭配 Control、Option 或 Command；不要使用常用编辑快捷键。") }
        guard check != select else { return UIText.t("两个快捷键不能相同。") }
        hotkey = nil; selectHotkey = nil
        let oldCheck = checkShortcut, oldSelect = selectShortcut
        checkShortcut = check; selectShortcut = select
        registerShortcuts()
        if hotkey == nil || selectHotkey == nil {
            let failed = hotkey == nil ? check.label : select.label
            hotkey = nil; selectHotkey = nil
            checkShortcut = oldCheck; selectShortcut = oldSelect
            registerShortcuts()
            return UIText.t("快捷键 %@ 已被其他软件占用，请换一个。", failed)
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(check), forKey: "helper.checkShortcut")
        UserDefaults.standard.set(try? JSONEncoder().encode(select), forKey: "helper.selectShortcut")
        return nil
    }
    @objc private func openShortcutSettings() {
        shortcutSettings.show(check: checkShortcut, select: selectShortcut) { [weak self] check, select in self?.saveShortcuts(check, select) }
    }
    @objc private func checkFromMenu() { startCheck() }
    @objc private func selectFromMenu() { startCheck(selectAll: true) }
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

    func check(selectAll: Bool = false) async {
        panel.close(); session = nil; model.invalidate()
        guard AXIsProcessTrusted() else {
            requestAccessibility()
            panel.show(notice: UIText.t("请先在“系统设置 → 隐私与安全性 → 辅助功能”里允许 NaturalKana Helper，再按 %@。", shortcut), near: nil)
            return
        }
        await Keystrokes.waitForModifiersReleased()
        guard !Task.isCancelled else { return }
        let app = NSWorkspace.shared.frontmostApplication
        var field = FocusedField.current()
        if field?.isSecure == true || IsSecureEventInputEnabled() {
            panel.show(notice: UIText.t("这是密码输入框，不会检查。"), near: nil); return
        }
        if selectAll {
            guard let app else { return }
            if let field, let value = field.value, !value.isEmpty,
               field.select(NSRange(location: 0, length: value.utf16.count)), field.selectedText == value {
                // Accessibility can select exactly this input field.
            } else {
                guard await Keystrokes.selectAll(in: app.processIdentifier) else { return }
            }
            field = FocusedField.current()
        }
        guard !Task.isCancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == app?.processIdentifier else { return }
        let text: String, source: Source
        var anchor: NSRect?
        if let field, let value = field.value, let selection = field.selectedRange {
            switch FieldDraft.make(value: value, selection: selection) {
            case .success(let draft):
                text = draft.text; source = .field(field, draft.range); anchor = field.bounds(for: draft.range)
            case .failure(let problem):
                panel.show(notice: message(problem), near: field.bounds(for: selection)); return
            }
        } else if let field, let selected = field.selectedText, !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = selected; source = .selection(field, field.selectedRange); anchor = field.selectedRange.flatMap(field.bounds(for:)) ?? field.frame
        } else if let copied = await Keystrokes.copySelection(in: app?.processIdentifier), !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = copied; source = .copied(field); anchor = field?.frame
        } else {
            panel.show(notice: UIText.t("这个 App 不提供输入框里的文字。请先选中要检查的那一句，再按 %@。", shortcut), near: field?.frame); return
        }
        guard !Task.isCancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == app?.processIdentifier else { return }
        guard !text.contains(where: \.isNewline) else { panel.show(notice: message(.multiline), near: anchor); return }
        guard text.count <= 200 else { panel.show(notice: message(.tooLong), near: anchor); return }
        let snapshot = DraftSnapshot(text: text, fieldID: "helper-" + UUID().uuidString, appID: app?.bundleIdentifier ?? "")
        session = Session(app: app, source: source, snapshot: snapshot)
        panel.show(model: model, original: text, near: anchor, accept: { [weak self] index in
                       self?.runOperation { [weak self] in await self?.accept(index) }
                   },
                   dismiss: { [weak self] in self?.dismiss() },
                   dismissOnOutsideClick: { [weak self] in self?.dismiss(restoreFocus: false) })
        model.update(snapshot, explicit: true)
    }

    private func message(_ problem: FieldDraft.Problem) -> String {
        switch problem {
        case .empty: UIText.t("光标所在的这一行是空的。")
        case .multiline: UIText.t("一次只能检查一句话，请只选中一行。")
        case .tooLong: UIText.t("这一行超过 200 字。请选中要检查的那一句，再按 %@。", shortcut)
        }
    }

    private func dismiss(restoreFocus: Bool = true) {
        operation?.cancel()
        panel.close(); model.dismiss()
        if restoreFocus { session?.app?.activate() }
        session = nil
    }

    private func accept(_ index: Int) async {
        guard let session, let text = model.accept(index, snapshot: session.snapshot) else { dismiss(); return }
        self.session = nil
        panel.close()
        let original = session.snapshot.text
        guard let app = session.app, !app.isTerminated else { return }
        app.activate()
        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard !Task.isCancelled, Keystrokes.canEdit(app.processIdentifier) else { return }
        switch session.source {
        case .field(let field, let range):
            guard field.isFocused, let value = field.value, NSMaxRange(range) <= value.utf16.count,
                  (value as NSString).substring(with: range) == original else { replacementFailed(text); return }
            if field.replace(range, with: text) { return }
            // A partially successful Accessibility edit must never be pasted a second time.
            guard field.value == value, field.select(range) else { replacementFailed(text); return }
            guard await Keystrokes.copySelection(in: app.processIdentifier) == original else { replacementFailed(text); return }
            _ = await Keystrokes.paste(text, in: app.processIdentifier)
        case .selection(let field, let range):
            guard field?.isFocused != false else { replacementFailed(text); return }
            if let field, let range { _ = field.select(range) }
            await replaceSelection(original: original, with: text, app: app, field: field)
        case .copied(let field):
            await replaceSelection(original: original, with: text, app: app, field: field)
        }
    }

    private func replaceSelection(original: String, with text: String, app: NSRunningApplication, field: FocusedField?) async {
        guard field?.isFocused != false else { replacementFailed(text); return }
        var selected = await Keystrokes.copySelection(in: app.processIdentifier)
        if selected != original {
            // Clicking a suggestion can clear WeChat's selection. Restore it only if the entire draft still matches.
            guard await Keystrokes.selectAll(in: app.processIdentifier) else { return }
            selected = await Keystrokes.copySelection(in: app.processIdentifier)
        }
        guard !Task.isCancelled else { return }
        guard selected == original, field?.isFocused != false else { replacementFailed(text); return }
        _ = await Keystrokes.paste(text, in: app.processIdentifier)
    }
    private func replacementFailed(_ text: String) {
        guard !Task.isCancelled else { return }
        copyInstead(text, UIText.t("原句或选区已经变了，未替换。建议已复制，请重新选中原句。"))
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
    private var outsideClick: (() -> Void)?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    /// Where the user dragged the panel, relative to its automatic position; kept across checks.
    private static let offsetKey = "NaturalKanaHelperPanelOffset"
    private var offset = NSSize(width: UserDefaults.standard.double(forKey: "\(offsetKey).x"), height: UserDefaults.standard.double(forKey: "\(offsetKey).y"))
    private var automaticOrigin = NSPoint.zero
    private var positioning = false
    private var moveObserver: NSObjectProtocol?

    init() {
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.movedByUser() }
        }
    }
    private func movedByUser() {
        guard !positioning, window.isVisible else { return }
        offset = NSSize(width: window.frame.minX - automaticOrigin.x, height: window.frame.minY - automaticOrigin.y)
        UserDefaults.standard.set(offset.width, forKey: "\(Self.offsetKey).x")
        UserDefaults.standard.set(offset.height, forKey: "\(Self.offsetKey).y")
    }
    /// Double-clicking the handle puts the panel back under the sentence.
    func resetPosition() {
        offset = .zero
        UserDefaults.standard.removeObject(forKey: "\(Self.offsetKey).x")
        UserDefaults.standard.removeObject(forKey: "\(Self.offsetKey).y")
        fit()
    }
    var dragHandle: AnyView {
        AnyView(PanelDragHandle { [weak self] in self?.resetPosition() }
            .frame(width: 30, height: 24)
            .overlay { Image(systemName: "line.3.horizontal").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).allowsHitTesting(false) }
            .help(UIText.t("拖动可移动建议框，双击恢复默认位置")))
    }

    func show(model: SuggestionModel, original: String, near anchor: NSRect?, accept: @escaping (Int) -> Void, dismiss: @escaping () -> Void, dismissOnOutsideClick: @escaping () -> Void) {
        hideTask?.cancel()
        window.onCancel = dismiss
        outsideClick = dismissOnOutsideClick
        window.onKey = { event in
            if event.keyCode == UInt16(kVK_Escape) { dismiss(); return true }
            if let digit = event.charactersIgnoringModifiers.flatMap(Int.init), (1...9).contains(digit), digit <= model.suggestions.count {
                accept(digit - 1); return true
            }
            return false
        }
        present(HelperPanelView(model: model, original: original, dragHandle: dragHandle, accept: accept, dismiss: dismiss), near: anchor)
    }
    /// A short message that closes by itself.
    func show(notice: String, near anchor: NSRect?) {
        hideTask?.cancel()
        window.onCancel = { [weak self] in self?.close() }
        outsideClick = { [weak self] in self?.close() }
        window.onKey = { [weak self] _ in self?.close(); return true }
        present(NoticeView(text: notice), near: anchor)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { self?.close() }
        }
    }
    func close() {
        hideTask?.cancel(); window.orderOut(nil)
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        globalClickMonitor = nil; localClickMonitor = nil; outsideClick = nil
    }

    private func watchOutsideClicks() {
        guard globalClickMonitor == nil, localClickMonitor == nil else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            MainActor.assumeIsolated { self?.outsideClick?() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window !== self.window { self.outsideClick?() }
            }
            return event
        }
    }

    private func present(_ view: some View, near anchor: NSRect?) {
        self.anchor = anchor ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        window.contentView = NSHostingView(rootView: view)
        fit()
        window.makeKeyAndOrderFront(nil)
        watchOutsideClicks()
    }
    /// Keeps the panel just below the sentence (above it near the bottom of the screen) as its content changes.
    func fit() {
        guard let content = window.contentView, let anchor else { return }
        let size = content.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor.insetBy(dx: -1, dy: -1)) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = min(max(anchor.minX, screen.minX), screen.maxX - size.width)
        let below = anchor.minY - size.height - 6
        let y = below >= screen.minY ? below : min(anchor.maxY + 6, screen.maxY - size.height)
        automaticOrigin = NSPoint(x: x, y: y)
        // Keep the top edge where the user left it while the content grows or shrinks.
        let origin = NSPoint(x: min(max(x + offset.width, screen.minX), screen.maxX - size.width),
                             y: min(max(y + offset.height, screen.minY), screen.maxY - size.height))
        positioning = true
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        positioning = false
    }
}

private struct HelperPanelView: View {
    @ObservedObject var model: SuggestionModel
    let original: String
    let dragHandle: AnyView
    let accept: (Int) -> Void
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.suggestions.isEmpty {
                HStack(spacing: 8) {
                    dragHandle
                    SuggestionStatusIndicator(status: model.status == .idle ? .requesting : model.status)
                    Text(model.status == .idle || model.status == .waiting ? UIText.t("正在获取建议…") : model.status.message)
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain)
                        .accessibilityLabel(UIText.t("关闭提示"))
                }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            } else {
                SuggestionStrip(suggestions: model.suggestions, language: model.suggestionLanguage, original: original,
                                highlightChanges: model.settings.highlightChanges, dragHandle: dragHandle, dismiss: dismiss, accept: accept)
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
