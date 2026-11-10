import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

/// A key combination, stored as a Carbon key code plus Cocoa modifier flags.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt  // NSEvent.ModifierFlags raw value (device independent subset)

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    var display: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + Shortcut.keyName(keyCode)
    }

    func matches(_ event: NSEvent) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return UInt32(event.keyCode) == keyCode && event.modifierFlags.intersection(relevant) == flags.intersection(relevant)
    }

    static func keyName(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Return: return "↩"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_Tab: return "⇥"
        default: break
        }
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var len = 0
        data.withUnsafeBytes { raw in
            let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
        }
        return String(utf16CodeUnits: chars, count: len).uppercased()
    }

    static let defaultActivate = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue)
    static let defaultPasteStack = Shortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue)
    static let defaultNextPinboard = Shortcut(keyCode: UInt32(kVK_RightArrow), modifiers: NSEvent.ModifierFlags.command.rawValue)
    static let defaultPrevPinboard = Shortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: NSEvent.ModifierFlags.command.rawValue)
}

enum HistoryRetention: Int, CaseIterable {
    case day, week, month, year, forever

    var label: String { ["Day", "Week", "Month", "Year", "Forever"][rawValue] }

    var interval: TimeInterval? {
        switch self {
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 31 * 86_400
        case .year: 366 * 86_400
        case .forever: nil
        }
    }
}

enum PasteDestination: String { case activeApp, clipboard }

enum ModifierChoice: String, CaseIterable, Identifiable {
    case command, option, control, shift
    var id: String { rawValue }
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .command: .command
        case .option: .option
        case .control: .control
        case .shift: .shift
        }
    }
    var label: String {
        switch self {
        case .command: "⌘ Command"
        case .option: "⌥ Option"
        case .control: "⌃ Control"
        case .shift: "⇧ Shift"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var soundEffects: Bool { didSet { d.set(soundEffects, forKey: "soundEffects") } }
    @Published var pasteDestination: PasteDestination { didSet { d.set(pasteDestination.rawValue, forKey: "pasteDestination") } }
    @Published var alwaysPlainText: Bool { didSet { d.set(alwaysPlainText, forKey: "alwaysPlainText") } }
    @Published var retention: HistoryRetention { didSet { d.set(retention.rawValue, forKey: "retention") } }
    @Published var showDuringScreenSharing: Bool { didSet { d.set(showDuringScreenSharing, forKey: "showDuringScreenSharing") } }
    @Published var linkPreviews: Bool { didSet { d.set(linkPreviews, forKey: "linkPreviews") } }
    @Published var ignoreConfidential: Bool { didSet { d.set(ignoreConfidential, forKey: "ignoreConfidential") } }
    @Published var ignoreTransient: Bool { didSet { d.set(ignoreTransient, forKey: "ignoreTransient") } }
    @Published var ignoredApps: [String] { didSet { d.set(ignoredApps, forKey: "ignoredApps") } }
    @Published var showInMenuBar: Bool { didSet { d.set(showInMenuBar, forKey: "showInMenuBar") } }
    @Published var activateShortcut: Shortcut? { didSet { save(activateShortcut, "activateShortcut") } }
    @Published var pasteStackShortcut: Shortcut? { didSet { save(pasteStackShortcut, "pasteStackShortcut") } }
    @Published var nextPinboardShortcut: Shortcut? { didSet { save(nextPinboardShortcut, "nextPinboardShortcut") } }
    @Published var prevPinboardShortcut: Shortcut? { didSet { save(prevPinboardShortcut, "prevPinboardShortcut") } }
    @Published var quickPasteModifier: ModifierChoice { didSet { d.set(quickPasteModifier.rawValue, forKey: "quickPasteModifier") } }
    @Published var plainTextModifier: ModifierChoice { didSet { d.set(plainTextModifier.rawValue, forKey: "plainTextModifier") } }
    @Published var pausedUntil: Date? { didSet { d.set(pausedUntil, forKey: "pausedUntil") } }
    @Published var iCloudSync: Bool { didSet { d.set(iCloudSync, forKey: "iCloudSync"); SyncEngine.shared.settingChanged() } }

    /// Stable per-Mac identifier used to name this device's snapshot in iCloud Drive.
    lazy var deviceID: String = {
        if let id = d.string(forKey: "deviceID") { return id }
        let id = UUID().uuidString; d.set(id, forKey: "deviceID"); return id
    }()

    @Published var openAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            guard openAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if openAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Open at login failed: \(error)")
                DispatchQueue.main.async { self.openAtLogin = SMAppService.mainApp.status == .enabled }
            }
        }
    }

    var isPaused: Bool {
        guard let p = pausedUntil else { return false }
        return p > Date()
    }

    private init() {
        d.register(defaults: [
            "soundEffects": true, "pasteDestination": PasteDestination.activeApp.rawValue,
            "alwaysPlainText": false, "retention": HistoryRetention.month.rawValue,
            "showDuringScreenSharing": true, "linkPreviews": true,
            "ignoreConfidential": true, "ignoreTransient": true, "showInMenuBar": true,
            "ignoredApps": ["com.bitwarden.desktop", "com.apple.keychainaccess", "com.apple.Passwords",
                            "com.1password.1password", "com.agilebits.onepassword7"],
            "quickPasteModifier": ModifierChoice.command.rawValue,
            "plainTextModifier": ModifierChoice.shift.rawValue,
            "iCloudSync": true,
        ])
        soundEffects = d.bool(forKey: "soundEffects")
        pasteDestination = PasteDestination(rawValue: d.string(forKey: "pasteDestination") ?? "") ?? .activeApp
        alwaysPlainText = d.bool(forKey: "alwaysPlainText")
        retention = HistoryRetention(rawValue: d.integer(forKey: "retention")) ?? .month
        showDuringScreenSharing = d.bool(forKey: "showDuringScreenSharing")
        linkPreviews = d.bool(forKey: "linkPreviews")
        ignoreConfidential = d.bool(forKey: "ignoreConfidential")
        ignoreTransient = d.bool(forKey: "ignoreTransient")
        ignoredApps = d.stringArray(forKey: "ignoredApps") ?? []
        showInMenuBar = d.bool(forKey: "showInMenuBar")
        quickPasteModifier = ModifierChoice(rawValue: d.string(forKey: "quickPasteModifier") ?? "") ?? .command
        plainTextModifier = ModifierChoice(rawValue: d.string(forKey: "plainTextModifier") ?? "") ?? .shift
        pausedUntil = d.object(forKey: "pausedUntil") as? Date
        iCloudSync = d.bool(forKey: "iCloudSync")
        activateShortcut = Self.load("activateShortcut", default: .defaultActivate)
        pasteStackShortcut = Self.load("pasteStackShortcut", default: .defaultPasteStack)
        nextPinboardShortcut = Self.load("nextPinboardShortcut", default: .defaultNextPinboard)
        prevPinboardShortcut = Self.load("prevPinboardShortcut", default: .defaultPrevPinboard)
    }

    private static func load(_ key: String, default def: Shortcut) -> Shortcut? {
        let d = UserDefaults.standard
        if d.object(forKey: key + ".cleared") != nil { return nil }
        guard let data = d.data(forKey: key), let s = try? JSONDecoder().decode(Shortcut.self, from: data) else { return def }
        return s
    }

    private func save(_ s: Shortcut?, _ key: String) {
        if let s, let data = try? JSONEncoder().encode(s) {
            d.set(data, forKey: key); d.removeObject(forKey: key + ".cleared")
        } else {
            d.removeObject(forKey: key); d.set(true, forKey: key + ".cleared")
        }
    }

    func resetShortcuts() {
        activateShortcut = .defaultActivate
        pasteStackShortcut = .defaultPasteStack
        nextPinboardShortcut = .defaultNextPinboard
        prevPinboardShortcut = .defaultPrevPinboard
        quickPasteModifier = .command
        plainTextModifier = .shift
    }
}
