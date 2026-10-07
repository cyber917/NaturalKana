#if os(macOS)
import AppKit
import InputMethodKit
import Carbon
import Combine
import SwiftUI
import NaturalSuggestCore

@MainActor public final class NativeSuggestionActivity: ObservableObject {
    public static let shared = NativeSuggestionActivity()
    @Published public var message = "等待输入"
    @Published public var inspectedText = ""
    @Published public var contextSource = "尚未取到文字"
    @Published public var lastRequest = "尚未发起请求"
    @Published public var timing = ""
    private init() {}
    public func record(_ status: Diagnostics) {
        guard status != .idle else { return }
        message = status.message
        switch status {
        case .disabled, .filtered, .waiting: break
        default: lastRequest = status.message
        }
    }
}

private final class SuggestionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor public final class NaturalMacSession {
    public let model = SuggestionModel()
    private let panel = SuggestionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private var fieldID = UUID().uuidString
    private var client: (any IMKTextInput)?
    private var snapshot: DraftSnapshot?
    private var replacement = NSRange(location: NSNotFound, length: 0)
    private var original = ""
    private var selectionAnchor = NSRange(location: NSNotFound, length: 0)
    private var markedAnchor = NSRange(location: NSNotFound, length: 0)
    private var discardComposition: (() -> Void)?
    private var recentDraft = RecentDraft()
    private var lastCaret = NSRect.zero
    private var captureTask: Task<Void, Never>?
    private var expectedCommittedEnd: Int?
    public init() {
        // The host editor stays active while an IME displays candidates. A panel
        // that hides with our inactive application can disappear immediately.
        panel.isFloatingPanel = true; panel.level = .popUpMenu; panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        model.onStatusChange = { [weak self] status in
            NativeSuggestionActivity.shared.record(status)
            if let timing = self?.model.timingText, !timing.isEmpty { NativeSuggestionActivity.shared.timing = timing }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.render(self.model.suggestions)
            }
        }
    }
    public func reset() { captureTask?.cancel(); captureTask = nil; model.cancel(); panel.orderOut(nil); snapshot = nil; client = nil; expectedCommittedEnd = nil; recentDraft.reset(); lastCaret = .zero; fieldID = UUID().uuidString }
    public func keyChanged(_ event: NSEvent) {
        let pendingCapture = captureTask != nil
        captureTask?.cancel(); captureTask = nil
        model.invalidate(); panel.orderOut(nil); snapshot = nil
        // Marked ranges change as part of normal composition. Only invalidate a
        // settled caret jump, not the cursor movement caused by our own commit.
        if let client, !pendingCapture, client.markedRange().location == NSNotFound {
            let selected = client.selectedRange()
            if selected != selectionAnchor, selected.location != expectedCommittedEnd { recentDraft.reset() }
        }
        if [51, 117, 115, 119, 123, 124, 125, 126].contains(event.keyCode) || event.modifierFlags.contains(.command) { recentDraft.reset() }
    }
    public func recordCommit(_ text: String, client: any IMKTextInput) {
        recentDraft.recordCommit(text)
        let marked = client.markedRange()
        let selected = client.selectedRange()
        let start = marked.location != NSNotFound ? marked.location : selected.location
        expectedCommittedEnd = start == NSNotFound ? nil : start + text.utf16.count
    }
    public func handleAcceptance(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.control],
              let character = event.charactersIgnoringModifiers,
              let index = model.settings.acceptKeys.firstIndex(of: character), index < model.suggestions.count else { return false }
        accept(index, fromKeyboard: true); return true
    }
    public func handleDismissal(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53,
              event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
              panel.isVisible || !model.suggestions.isEmpty || model.status == .waiting || model.status == .requesting else { return false }
        dismiss(); return true
    }
    public func dismiss() {
        captureTask?.cancel(); captureTask = nil
        model.dismiss(); panel.orderOut(nil); snapshot = nil
        NativeSuggestionActivity.shared.message = "已关闭建议"
    }
    public func update(client: any IMKTextInput, composition: String, unconvertedLatin: Bool, discardComposition: @escaping () -> Void) {
        captureTask?.cancel()
        let appID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        // insertText/setMarkedText may settle asynchronously in the host. Reading
        // immediately in the XPC response callback can observe the previous caret.
        captureTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(75)) } catch { return }
            guard let self, !Task.isCancelled,
                  appID == (NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "") else { return }
            self.captureTask = nil
            self.capture(client: client, composition: composition, unconvertedLatin: unconvertedLatin, discardComposition: discardComposition)
        }
    }
    private func capture(client: any IMKTextInput, composition: String, unconvertedLatin: Bool, discardComposition: @escaping () -> Void) {
        model.reload()
        let appID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        guard model.settings.enabled, model.settings.consent, !IsSecureEventInputEnabled(),
              !model.settings.blockedApps.contains(appID) else { reset(); NativeSuggestionActivity.shared.message = model.settings.enabled && model.settings.consent ? "当前应用或输入框已禁用建议" : Diagnostics.disabled.message; return }
        self.client = client; self.discardComposition = discardComposition
        let marked = client.markedRange(); let selected = client.selectedRange()
        selectionAnchor = selected; markedAnchor = marked
        // InputMethodKit ranges are UTF-16. Never subtract Swift Character counts from them.
        let end = marked.location != NSNotFound ? marked.location : selected.location
        guard selected.length == 0 || marked.location != NSNotFound else { keyChangedForSelection(); return }
        var prefix: String?
        var prefixRange = NSRange(location: NSNotFound, length: 0)
        if end != NSNotFound {
            let start = max(0, end - 400)
            let range = NSRange(location: start, length: end - start)
            // IMK's string API works in hosts that do not implement attributedSubstring.
            if let value = client.string(from: range, actualRange: &prefixRange),
               prefixRange.location != NSNotFound, NSMaxRange(prefixRange) == end, value.utf16.count == prefixRange.length {
                prefix = value
            } else if let value = client.attributedSubstring(from: range)?.string, value.utf16.count == range.length {
                prefix = value; prefixRange = range
            }
        }
        let text = recentDraft.text(hostPrefix: prefix, composition: composition)
        NativeSuggestionActivity.shared.inspectedText = text
        NativeSuggestionActivity.shared.contextSource = prefix != nil ? "输入框上下文" : "本次输入会话的已提交文字"
        let snap = DraftSnapshot(text: text, fieldID: fieldID, composingLatin: unconvertedLatin, appID: appID)
        let markedLength = marked.location != NSNotFound ? marked.length : 0
        // A fallback may generate suggestions, but replacement still requires host verification.
        if prefix != nil, end != NSNotFound, end + markedLength >= text.utf16.count, !text.isEmpty {
            let range = NSRange(location: end + markedLength - text.utf16.count, length: text.utf16.count)
            if read(client, range: range) == text {
                replacement = range; original = text
            }
            else { replacement = NSRange(location: NSNotFound, length: 0); original = "" }
        } else { replacement = NSRange(location: NSNotFound, length: 0); original = "" }
        snapshot = snap; model.update(snap)
    }
    private func keyChangedForSelection() { model.invalidate(); recentDraft.reset(); snapshot = nil; panel.orderOut(nil) }
    private func read(_ client: any IMKTextInput, range: NSRange) -> String? {
        var actual = NSRange(location: NSNotFound, length: 0)
        if let value = client.string(from: range, actualRange: &actual), actual == range { return value }
        return client.attributedSubstring(from: range)?.string
    }
    private func render(_ items: [Suggestion]) {
        guard (!items.isEmpty || SuggestionStatusIndicator.isVisible(model.status)), items == model.suggestions, !IsSecureEventInputEnabled(), let client, let snapshot,
              snapshot.appID == (NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""),
              client.selectedRange() == selectionAnchor, client.markedRange() == markedAnchor else {
            if !items.isEmpty { NativeSuggestionActivity.shared.message = "建议已生成，但文字、光标或前台应用已变化，已取消显示" }
            panel.orderOut(nil); return
        }
        if items.isEmpty {
            panel.contentView = NSHostingView(rootView: HStack(spacing: 6) {
                SuggestionStatusIndicator(status: model.status)
                Button { [weak self] in self?.dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(.secondary)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }.buttonStyle(.plain).help(model.settings.language.closeTitle + " (Esc)").accessibilityLabel(model.settings.language.closeTitle)
            }.padding(5).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)))
        } else {
            panel.contentView = NSHostingView(rootView: SuggestionStrip(suggestions: items, language: model.settings.language, copiesOnly: replacement.location == NSNotFound || replacement != markedAnchor, original: model.suggestionDraft, highlightChanges: model.settings.highlightChanges, dismiss: { [weak self] in self?.dismiss() }) { [weak self] in self?.accept($0) }.frame(width: 480))
        }
        let size = panel.contentView?.fittingSize ?? NSSize(width: 360, height: 90)
        var caret = NSRect.zero
        for index in [client.selectedRange().location, client.markedRange().location, 0] where index != NSNotFound {
            _ = client.attributes(forCharacterIndex: index, lineHeightRectangle: &caret)
            if caret != .zero { break }
        }
        if caret == .zero { caret = lastCaret } else { lastCaret = caret }
        guard caret != .zero else { NativeSuggestionActivity.shared.message = "建议已生成，但此应用没有提供光标位置"; panel.orderOut(nil); return }
        let screen = NSScreen.screens.first { $0.frame.intersects(caret) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let width = items.isEmpty ? 56 : min(500, max(260, size.width))
        let height = items.isEmpty ? 30 : min(340, max(45, size.height))
        let x = min(max(caret.minX, screen.minX), screen.maxX - width)
        let y = caret.maxY + height + 6 <= screen.maxY ? caret.maxY + 6 : caret.minY - height - 6
        panel.setFrame(NSRect(x: x, y: max(screen.minY, y), width: width, height: height), display: true)
        NativeSuggestionActivity.shared.message = items.isEmpty ? model.status.message : "已显示 \(items.count) 条建议"
        panel.alphaValue = 0; panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.10; panel.animator().alphaValue = 1 }
    }
    private func accept(_ index: Int, fromKeyboard: Bool = false) {
        guard let client, let snapshot, !IsSecureEventInputEnabled(),
              client.selectedRange() == selectionAnchor, client.markedRange() == markedAnchor,
              snapshot.appID == (NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "") else { reset(); return }
        if replacement.location != NSNotFound {
            guard read(client, range: replacement) == original else { reset(); return }
        }
        guard let text = model.accept(index, snapshot: snapshot) else { reset(); return }
        // Palette clicks occur outside the host's input-event dispatch. Some
        // Cocoa clients then discard replacementRange. Keyboard acceptance keeps
        // the verified full-range path; clicks only replace the active composition.
        if replacement.location != NSNotFound, fromKeyboard || replacement == markedAnchor {
            discardComposition?(); client.insertText(text, replacementRange: replacement)
        } else {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
            NativeSuggestionActivity.shared.message = "此应用不支持这段文字的安全替换；建议已复制，请选中原句后粘贴"
        }
        panel.orderOut(nil); self.snapshot = nil
    }
}
#endif
