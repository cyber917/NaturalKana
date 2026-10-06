import AppKit
import Carbon
import ApplicationServices

@MainActor final class ProbeTextView: NSTextView {
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let text = (insertString as? String) ?? (insertString as? NSAttributedString)?.string ?? ""
        print("Host insert: length", text.utf16.count, "requested", replacementRange, "marked", markedRange(), "selected", selectedRange())
        fflush(stdout)
        super.insertText(insertString, replacementRange: replacementRange)
    }
}
@MainActor final class HostProbe: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var input: NSTextView!
    var original: TISInputSource?
    var savedPasteboard: [[NSPasteboard.PasteboardType: Data]]?
    let target = "org.naturalkana.inputmethod.Japanese"
    func finish(_ success: Bool, _ message: String) {
        if let savedPasteboard {
            let board = NSPasteboard.general; board.clearContents()
            let items = savedPasteboard.map { values in
                let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item
            }
            board.writeObjects(items)
        }
        if let original { _ = TISSelectInputSource(original) }
        print(message); fflush(stdout)
        exit(success ? 0 : 1)
    }
    func key(_ code: UInt16, flags: CGEventFlags = []) async -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid(), window.isKeyWindow else {
            finish(false, "STOP: test window lost focus; no further keys sent"); return false
        }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            event.flags = flags
            event.postToPid(getpid())
            try? await Task.sleep(for: .milliseconds(35))
        }
        try? await Task.sleep(for: .milliseconds(100))
        return true
    }
    func acceptThirdCandidate() async -> Bool {
        await Task.detached {
        func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?; AXUIElementCopyAttributeValue(e, name as CFString, &value); return value
        }
        func walk(_ e: AXUIElement, _ depth: Int = 0) -> [AXUIElement] {
            guard depth < 20 else { return [] }
            return [e] + ((attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []).flatMap { walk($0, depth + 1) }
        }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "org.naturalkana.inputmethod") {
            for item in walk(AXUIElementCreateApplication(app.processIdentifier)) where (attr(item, kAXRoleAttribute) as? String) == kAXButtonRole {
                let label = attr(item, kAXTitleAttribute) as? String ?? attr(item, kAXDescriptionAttribute) as? String ?? ""
                let values = walk(item).compactMap { attr($0, kAXValueAttribute) as? String }
                if label.hasPrefix("3"), label.count > 5 {
                    print("Third candidate found:", label); fflush(stdout)
                    let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
                    print("AX press returned:", result.rawValue, "(host text determines success)")
                    return true
                }
                if values.contains("3"), values.contains(where: { $0.contains("友達") || $0.contains("仕事") }) {
                    print("Third candidate found in AX button children"); fflush(stdout)
                    let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
                    print("AX press returned:", result.rawValue, "(host text determines success)")
                    return true
                }
            }
        }
        return false
        }.value
    }
    func inspectRegisterLabels() async -> Bool {
        await Task.detached {
            func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
                var value: CFTypeRef?; AXUIElementCopyAttributeValue(e, name as CFString, &value); return value
            }
            func walk(_ e: AXUIElement, _ depth: Int = 0) -> [AXUIElement] {
                guard depth < 20 else { return [] }
                return [e] + ((attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []).flatMap { walk($0, depth + 1) }
            }
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: "org.naturalkana.inputmethod") {
                let windows = attr(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) as? [AXUIElement] ?? []
                for window in windows {
                    guard let rawSize = attr(window, kAXSizeAttribute), CFGetTypeID(rawSize) == AXValueGetTypeID() else { continue }
                    var size = CGSize.zero
                    guard AXValueGetValue(rawSize as! AXValue, .cgSize, &size), abs(size.width - 480) < 2 else { continue }
                    let texts = walk(window).filter { (attr($0, kAXRoleAttribute) as? String) == kAXStaticTextRole }
                        .compactMap { attr($0, kAXValueAttribute) as? String }
                    let headings = texts.filter { $0 == "カジュアル" || $0 == "丁寧" }
                    let hint = texts.contains("クリックでコピー・元の文を選択して貼り付け")
                    print("Popup register headings:", headings, "Japanese copy hint:", hint); fflush(stdout)
                    return headings == ["カジュアル", "丁寧"] && hint
                }
            }
            return false
        }.value
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard AXIsProcessTrusted() else { finish(false, "BLOCKED: Accessibility is not enabled for this test process"); return }
        if CommandLine.arguments.contains("--expect-copy") {
            savedPasteboard = (NSPasteboard.general.pasteboardItems ?? []).map { item in
                Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
            }
        }
        original = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 240), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "NaturalKana · 固定例句验收"
        input = ProbeTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 240))
        input.font = .systemFont(ofSize: 22)
        window.contentView = input
        window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(input)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            let filter = [kTISPropertyInputSourceID!: target] as CFDictionary
            guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource], let source = sources.first,
                  TISSelectInputSource(source) == noErr else { finish(false, "FAIL: cannot select installed Japanese input source"); return }
            input.inputContext?.activate()
            input.inputContext?.selectedKeyboardInputSource = target
            try? await Task.sleep(for: .seconds(1))
            let codes: [Character: UInt16] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,"n":45,"m":46]
            let segmented = CommandLine.arguments.contains("--segmented")
            let long = CommandLine.arguments.contains("--long")
            let chunks = long ? ["imaieniirudemoshigotogaarimasukarasukoshimattekudasai"] : (segmented ? ["kinou", "tomodachiwo", "aimashita"] : ["kinoutomodachiwoaimashita"])
            for chunk in chunks {
                for letter in chunk { guard await key(codes[letter]!) else { return } }
                guard await key(49) else { return }
                if !CommandLine.arguments.contains("--keep-composition") { guard await key(36) else { return } }
            }
            try? await Task.sleep(for: .seconds(1))
            print("Host final marked range:",input.markedRange()); fflush(stdout)
            let before = input.string
            print("Test field after IME commit: \(before)"); fflush(stdout)
            guard !before.contains("kinou"), (long ? before.contains("仕事") : before.contains("昨日")) else { finish(false, "FAIL: real key events did not convert the fixed phrase"); return }
            for tick in 0..<25 {
                try? await Task.sleep(for: .seconds(1))
                let nativePIDs = NSRunningApplication.runningApplications(withBundleIdentifier: "org.naturalkana.inputmethod").map(\.processIdentifier)
                let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                if tick % 5 == 0 {
                    for entry in windows where nativePIDs.contains(entry[kCGWindowOwnerPID as String] as? Int32 ?? -1) {
                        print("Native window layer \(entry[kCGWindowLayer as String] ?? -1), bounds \(entry[kCGWindowBounds as String] ?? [:])")
                    }
                    fflush(stdout)
                }
                let panel = windows.contains { entry in
                    guard let pid = entry[kCGWindowOwnerPID as String] as? Int32, nativePIDs.contains(pid),
                          let layer = entry[kCGWindowLayer as String] as? Int, layer == Int(CGWindowLevelForKey(.popUpMenuWindow)),
                          let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
                    return (bounds["Width"] ?? 0) >= 260 && (bounds["Height"] ?? 0) >= 45
                }
                if panel {
                    print("Candidate panel visible"); fflush(stdout)
                    if CommandLine.arguments.contains("--inspect-registers"), !(await inspectRegisterLabels()) {
                        finish(false, "FAIL: grouped Japanese popup labels were not observed"); return
                    }
                    if CommandLine.arguments.contains("--third") {
                        if !(await acceptThirdCandidate()) { continue }
                    } else {
                        guard await key(segmented ? 19 : 18, flags: .maskControl) else { return }
                    }
                    try? await Task.sleep(for: .seconds(1))
                    let after = input.string
                    if CommandLine.arguments.contains("--expect-copy") {
                        let copied = NSPasteboard.general.string(forType: .string) ?? ""
                        let passed = after == before && copied.contains("仕事") && copied.contains("待") && copied.components(separatedBy: "仕事").count == 2
                        finish(passed, "Copy fallback: draft unchanged, whole candidate copied, clipboard restored: \(passed ? "PASS" : "FAIL")")
                        return
                    }
                    let passed = after != before && (!long || after.components(separatedBy: "仕事").count == 2) && (long ? (after.contains("仕事") && after.contains("待")) : (after.contains("昨日") && after.contains("友達") && (after.contains("に会") || after.contains("と会"))))
                    finish(passed, "After candidate acceptance: \(after); replacement \(passed ? "PASS" : "FAIL")")
                    return
                }
            }
            finish(false, "FAIL: requested candidate was not observed/accepted within 25 seconds after commit")
        }
    }
}
let app = NSApplication.shared
let delegate = HostProbe()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
