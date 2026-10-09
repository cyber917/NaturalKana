#if os(macOS)
import AppKit
import ApplicationServices
import Carbon

/// The focused text element of the frontmost app, read and edited through Accessibility.
@MainActor struct FocusedField {
    let element: AXUIElement

    static func current() -> FocusedField? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return FocusedField(element: focused as! AXUIElement)
    }

    private func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    var isFocused: Bool {
        guard let current = Self.current() else { return false }
        return CFEqual(element, current.element) && !current.isSecure
    }
    var value: String? { attribute(kAXValueAttribute) as? String }
    var selectedText: String? { attribute(kAXSelectedTextAttribute) as? String }
    var selectedRange: NSRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
    /// Password fields must never be read or sent.
    var isSecure: Bool {
        (attribute(kAXSubroleAttribute) as? String) == kAXSecureTextFieldSubrole || IsSecureEventInputEnabled()
    }

    /// Screen rectangle of a text range in Cocoa coordinates (origin at the bottom left of the main screen).
    func bounds(for range: NSRange) -> NSRect? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var result: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &result) == .success,
           let result, CFGetTypeID(result) == AXValueGetTypeID() {
            var rect = CGRect.zero
            if AXValueGetValue(result as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 { return Self.cocoa(rect) }
        }
        return frame
    }
    var frame: NSRect? {
        guard let position = attribute(kAXPositionAttribute), let size = attribute(kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return Self.cocoa(CGRect(origin: point, size: extent))
    }
    private static func cocoa(_ rect: CGRect) -> NSRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Selects `range` and types `text` over it. True only when the field afterwards contains the text there.
    func replace(_ range: NSRange, with text: String) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let selection = AXValueCreate(.cfRange, &cfRange),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, selection) == .success,
              AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success,
              let after = value else { return false }
        let written = NSRange(location: range.location, length: text.utf16.count)
        return NSMaxRange(written) <= after.utf16.count && (after as NSString).substring(with: written) == text
    }
    /// Selects `range` so a following paste replaces it.
    func select(_ range: NSRange) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let selection = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, selection) == .success
    }
}

/// Copy/paste through the frontmost app, for apps whose text fields Accessibility cannot read or edit.
/// The user's clipboard is restored afterwards.
@MainActor enum Keystrokes {
    /// ⌃⌥ may still be held from the shortcut; a ⌘C sent meanwhile would become another key combination.
    static func waitForModifiersReleased() async {
        let held: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        for _ in 0..<100 where !CGEventSource.flagsState(.combinedSessionState).intersection(held).isEmpty {
            if Task.isCancelled { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
    static func press(_ key: Int, command: Bool = true) {
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down)
            // Do not leave Command held in the session state after a synthetic copy/select.
            event?.flags = command && down ? .maskCommand : []
            event?.post(tap: .cgSessionEventTap)
        }
    }
    static func canEdit(_ pid: pid_t?) -> Bool {
        guard let pid else { return false }
        let held: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        return CGEventSource.flagsState(.combinedSessionState).intersection(held).isEmpty
            && !Task.isCancelled && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            && !IsSecureEventInputEnabled() && FocusedField.current()?.isSecure != true
    }
    static func selectAll(in pid: pid_t) async -> Bool {
        await waitForModifiersReleased()
        guard canEdit(pid) else { return false }
        press(kVK_ANSI_A)
        try? await Task.sleep(for: .milliseconds(100))
        return canEdit(pid)
    }
    /// Copies the frontmost app's selection; nil when nothing was selected.
    static func copySelection(in pid: pid_t?) async -> String? {
        let board = NSPasteboard.general
        let saved = PasteboardContents(board)
        let before = board.changeCount
        await waitForModifiersReleased()
        guard canEdit(pid) else { return nil }
        press(kVK_ANSI_C)
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(40))
            if board.changeCount != before || Task.isCancelled { break }
        }
        let text = canEdit(pid) && board.changeCount != before ? board.string(forType: .string) : nil
        if board.changeCount != before { saved.restore(to: board) }
        return text
    }
    /// Pastes `text` over the frontmost app's selection, then restores the clipboard.
    static func paste(_ text: String, in pid: pid_t) async -> Bool {
        let board = NSPasteboard.general
        let saved = PasteboardContents(board)
        await waitForModifiersReleased()
        guard canEdit(pid) else { return false }
        board.clearContents(); board.setString(text, forType: .string)
        let written = board.changeCount
        press(kVK_ANSI_V)
        // The target reads the pasteboard asynchronously.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { continuation.resume() }
        }
        if board.changeCount == written { saved.restore(to: board) }
        return true
    }
}

private struct PasteboardContents {
    let items: [[NSPasteboard.PasteboardType: Data]]
    init(_ board: NSPasteboard) {
        items = (board.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }
    func restore(to board: NSPasteboard) {
        board.clearContents()
        guard !items.isEmpty else { return }
        board.writeObjects(items.map { contents in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        })
    }
}
#endif
