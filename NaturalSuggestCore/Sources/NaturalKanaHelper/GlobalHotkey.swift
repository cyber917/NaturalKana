#if os(macOS)
import Carbon

/// A system-wide shortcut via Carbon. Unlike event taps it needs no permission.
@MainActor final class GlobalHotkey {
    nonisolated(unsafe) private var hotKey: EventHotKeyRef?
    nonisolated(unsafe) private var handler: EventHandlerRef?
    private let identifier: UInt32
    private let action: @MainActor () -> Void

    init?(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.identifier = id
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated {
                guard id.signature == 0x4E4B_4850, id.id == hotkey.identifier else { return OSStatus(eventNotHandledErr) }
                hotkey.action()
                return noErr
            }
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return nil }
        let keyID = EventHotKeyID(signature: OSType(0x4E4B_4850), id: id)
        guard RegisterEventHotKey(keyCode, modifiers, keyID, GetApplicationEventTarget(), 0, &hotKey) == noErr else {
            if let handler { RemoveEventHandler(handler) }; handler = nil
            return nil
        }
    }
    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
#endif
