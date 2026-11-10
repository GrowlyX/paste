import AppKit
import Carbon.HIToolbox

/// System-wide hotkey via Carbon (works without Accessibility permission).
final class HotKey {
    private var ref: EventHotKeyRef?
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false
    private static var nextID: UInt32 = 1
    private let id: UInt32

    init?(_ shortcut: Shortcut, handler: @escaping () -> Void) {
        HotKey.installHandler()
        id = HotKey.nextID; HotKey.nextID += 1
        let hkID = EventHotKeyID(signature: OSType(0x5053_5445), id: id)  // 'PSTE'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        HotKey.handlers[id] = handler
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.handlers[id] = nil
    }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            debugLog("hotkey id=\(hk.id) registered=\(HotKey.handlers[hk.id] != nil)")
            if let h = HotKey.handlers[hk.id] { DispatchQueue.main.async(execute: h) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// Diagnostic logging, enabled by launching with PASTE_DEBUG=1.
let debugEnabled = ProcessInfo.processInfo.environment["PASTE_DEBUG"] != nil
func debugLog(_ message: @autoclosure () -> String) {
    if debugEnabled { NSLog("Paste: %@", message()) }
}
