import Foundation
import Carbon
import AppKit

// Installer utility: register/enable this input method without changing the current selection.
let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("Usage: register-input-source [--register|--list] app-path")
    exit(2)
}
let url = URL(fileURLWithPath: arguments[2]).standardizedFileURL
_ = NSApplication.shared
guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { exit(2) }
if arguments[1] == "--register" {
    let launchStatus = LSRegisterURL(url as CFURL, true)
    guard launchStatus == noErr else { print("Launch Services registration failed: \(launchStatus)"); exit(1) }
    let status = TISRegisterInputSource(url as CFURL)
    guard status == noErr else { print("Registration failed: \(status)"); exit(1) }
} else if arguments[1] != "--list" { exit(2) }
let filter = [kTISPropertyBundleID!: identifier] as CFDictionary
guard let result = TISCreateInputSourceList(filter, true) else {
    let total = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource]
    print("No matching input source yet; available source count: \(total?.count ?? 0)")
    exit(1)
}
let sources = result.takeRetainedValue() as! [TISInputSource]
func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
}
var records: [[String: Any]] = []
var failed = sources.isEmpty
for source in sources {
    let id = property(source, kTISPropertyInputSourceID) as? String ?? ""
    if arguments[1] == "--register", property(source, kTISPropertyInputSourceIsEnableCapable) as? Bool == true {
        let status = TISEnableInputSource(source)
        if status != noErr { print("Enable failed for \(id): \(status)"); failed = true }
    }
    records.append([
        "id": id,
        "name": property(source, kTISPropertyLocalizedName) as? String ?? "",
        "enableCapable": property(source, kTISPropertyInputSourceIsEnableCapable) as? Bool ?? false,
        "selectCapable": property(source, kTISPropertyInputSourceIsSelectCapable) as? Bool ?? false,
        "type": property(source, kTISPropertyInputSourceType) as? String ?? "",
        "enabled": property(source, kTISPropertyInputSourceIsEnabled) as? Bool ?? false,
        "selected": property(source, kTISPropertyInputSourceIsSelected) as? Bool ?? false
    ])
}
let json = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: json, as: UTF8.self))
if arguments[1] == "--register" {
    RunLoop.current.run(until: Date().addingTimeInterval(2))
    // Enabled child modes do not imply that their parent input method is enabled.
    // TISEnableInputSource can also return noErr without enabling the parent.
    let refreshed = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
    let parentEnabled = refreshed.contains {
        property($0, kTISPropertyInputSourceID) as? String == identifier &&
        property($0, kTISPropertyInputSourceIsEnabled) as? Bool == true
    }
    if !parentEnabled {
        print("Registered, but the input method is not enabled. Add NaturalKana in System Settings > Keyboard > Text Input > Edit > +.")
        exit(3)
    }
}
exit(failed ? 1 : 0)
