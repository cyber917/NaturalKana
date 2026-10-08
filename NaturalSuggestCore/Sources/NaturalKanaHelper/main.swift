#if os(macOS)
import AppKit

let helper = HelperApp()
NSApplication.shared.delegate = helper
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
#endif
