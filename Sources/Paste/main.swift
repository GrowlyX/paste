import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()

    private var hotKey: HotKey?
    private var stackHotKey: HotKey?
    /// Shortcuts that another app already owns (shown in Settings).
    private(set) var failedShortcuts: [String] = []
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = ClipStore.shared
        PanelController.shared.setup()
        ClipboardMonitor.shared.start()
        if ProcessInfo.processInfo.environment["PASTE_HOME"] == nil { SyncEngine.shared.start() }  // never sync a demo library
        SharedPinboards.shared.start()
        registerHotKey()
        updateStatusItem()
        backfillLinkPreviews()

        // First launch: show the shelf so people see what they've got.
        if !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { PanelController.shared.show() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PanelController.shared.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipStore.shared.saveLocal()
    }

    // MARK: Hotkey

    func registerHotKey() {
        hotKey = nil; stackHotKey = nil
        failedShortcuts = []
        if let s = AppSettings.shared.activateShortcut {
            hotKey = HotKey(s) { PanelController.shared.toggle() }
            if hotKey == nil { failedShortcuts.append(s.display) }
        }
        if let s = AppSettings.shared.pasteStackShortcut {
            stackHotKey = HotKey(s) { PasteStack.shared.toggle() }
            if stackHotKey == nil { failedShortcuts.append(s.display) }
        }
        if !failedShortcuts.isEmpty { NSLog("Paste: shortcuts already in use: %@", failedShortcuts.joined(separator: ", ")) }
    }

    func suspendHotKey() { hotKey = nil; stackHotKey = nil }

    // MARK: Menu bar

    func updateStatusItem() {
        guard AppSettings.shared.showInMenuBar else {
            if let s = statusItem { NSStatusBar.system.removeStatusItem(s) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let img = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Paste")
        img?.isTemplate = true
        item.button?.image = img
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    // MARK: Windows

    func openSettings(tab: SettingsTab? = nil) {
        if let tab { SettingsRouter.shared.tab = tab }
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.title = "Paste Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView()
                .environmentObject(AppSettings.shared).environmentObject(SyncEngine.shared))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Paste",
            .credits: NSAttributedString(string: "A clipboard manager for macOS.",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }

    private func backfillLinkPreviews() {
        for item in ClipStore.shared.items where item.kind == .link && !item.linkPreviewFetched {
            LinkPreviewer.shared.fetchIfNeeded(item.id)
        }
    }

    @objc func menuOpen() { PanelController.shared.show() }
    @objc func menuSettings() { openSettings() }
    @objc func menuStack() { PasteStack.shared.toggle() }
    @objc func menuPause(_ sender: NSMenuItem) {
        let s = AppSettings.shared
        s.pausedUntil = s.isPaused ? nil : Date().addingTimeInterval(TimeInterval(sender.tag))
    }
    @objc func menuQuit() { NSApp.terminate(nil) }
}

extension AppDelegate: NSMenuDelegate {
    /// Rebuilt every time so the shortcut and pause state are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = NSMenuItem(title: "Open Paste", action: #selector(menuOpen), keyEquivalent: "")
        if let s = AppSettings.shared.activateShortcut { open.title = "Open Paste   \(s.display)" }
        open.target = self
        menu.addItem(open)
        let stack = NSMenuItem(title: PasteStack.shared.isActive ? "Close Paste Stack" : "Open Paste Stack",
                               action: #selector(menuStack), keyEquivalent: "")
        stack.target = self
        menu.addItem(stack)
        menu.addItem(.separator())
        if AppSettings.shared.isPaused {
            let r = NSMenuItem(title: "Resume Paste", action: #selector(menuPause(_:)), keyEquivalent: "")
            r.target = self
            menu.addItem(r)
        } else {
            let pause = NSMenuItem(title: "Pause Paste", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (title, secs) in [("For 15 Minutes", 900), ("For 1 Hour", 3600), ("For 8 Hours", 28800), ("Until Resumed", 3_153_600_000)] {
                let i = NSMenuItem(title: title, action: #selector(menuPause(_:)), keyEquivalent: "")
                i.tag = secs; i.target = self
                sub.addItem(i)
            }
            pause.submenu = sub
            menu.addItem(pause)
        }
        let settings = NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Paste", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }
}

let app = NSApplication.shared

app.delegate = AppDelegate.shared
app.run()
