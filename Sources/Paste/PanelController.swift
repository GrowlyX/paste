import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless panel that can take keyboard focus without activating Paste,
/// so the app you were working in stays frontmost and receives the paste.
final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PanelController: NSObject, NSWindowDelegate {
    static let shared = PanelController()

    static let height: CGFloat = 332
    private var panel: ShelfPanel!
    private var previewPanel: NSPanel!
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var modalDepth = 0
    private(set) var isVisible = false
    private let model = PanelModel.shared

    func setup() {
        panel = ShelfPanel(contentRect: NSRect(x: 0, y: 0, width: 1200, height: Self.height),
                           styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                           backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let host = NSHostingView(rootView: ShelfView().environmentObject(model).environmentObject(ClipStore.shared)
            .environmentObject(AppSettings.shared).environmentObject(SyncEngine.shared))
        host.sizingOptions = []
        panel.contentView = host

        previewPanel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        previewPanel.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        previewPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        previewPanel.isOpaque = false
        previewPanel.backgroundColor = .clear
        previewPanel.hasShadow = true
        previewPanel.ignoresMouseEvents = false
        previewPanel.contentView = NSHostingView(rootView: PreviewContainer().environmentObject(model).environmentObject(ClipStore.shared))

        applySharing()
    }

    func applySharing() {
        let type: NSWindow.SharingType = AppSettings.shared.showDuringScreenSharing ? .readOnly : .none
        panel?.sharingType = type
        previewPanel?.sharingType = type
        PasteStack.shared.applySharing()
    }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        debugLog("show() visible=\(isVisible)")
        guard !isVisible else { return }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { model.targetApp = front }
        ClipStore.shared.prune()
        SyncEngine.shared.pull()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let target = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: Self.height)
        var start = target
        start.origin.y -= Self.height

        model.resetSelection()
        model.isKey = true
        panel.setFrame(start, display: false)
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
        reclaimAttempts = 0
        installMonitors()
        installDismissWatchers()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(target, display: true)
        }
    }

    func hide(animated: Bool = true) {
        debugLog("hide() visible=\(isVisible) from: \(Thread.callStackSymbols.dropFirst().prefix(3).map { $0.split(separator: " ").dropFirst(3).prefix(1).joined() }.joined(separator: " < "))")
        guard isVisible else { return }
        isVisible = false
        removeMonitors()
        removeDismissWatchers()
        model.previewItem = nil
        model.renamingItem = nil
        model.renamingPinboard = nil
        if model.editingItem != nil { model.finishEdit(save: nil) }
        model.quickPasteHeld = false
        previewPanel.orderOut(nil)
        let done = { [self] in
            panel.orderOut(nil)
            model.endSearch()
            model.list = model.list  // keep list; selection resets on next show
        }
        guard animated else { done(); return }
        var end = panel.frame
        end.origin.y -= Self.height
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(end, display: true)
        }, completionHandler: { if !self.isVisible { done() } })
    }

    /// Runs a modal (alert, open panel) without the shelf auto-hiding underneath it.
    func runModal<T>(_ body: () -> T) -> T {
        modalDepth += 1
        NSApp.activate(ignoringOtherApps: true)
        let result = body()
        modalDepth -= 1
        if isVisible { panel.makeKeyAndOrderFront(nil) }
        return result
    }

    /// Losing key focus does NOT close the shelf: some apps grab focus back right after we take it.
    /// We re-claim focus a couple of times; the shelf closes on an outside click or an app switch instead.
    private var reclaimAttempts = 0

    func windowDidResignKey(_ notification: Notification) {
        debugLog("resignKey; key window now: \(String(describing: NSApp.keyWindow))")
        guard modalDepth == 0, isVisible else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [self] in
            guard modalDepth == 0, isVisible, !panel.isKeyWindow, !CardDragger.shared.isDragging else { return }
            if let key = NSApp.keyWindow, key.className.contains("Popover") || key.className.contains("Menu") { return }
            if reclaimAttempts < 3 {
                reclaimAttempts += 1
                panel.makeKeyAndOrderFront(nil)
            } else {
                model.isKey = false
            }
        }
    }

    func windowDidBecomeKey(_ notification: Notification) { debugLog("becomeKey"); model.isKey = true }

    private var outsideClickMonitor: Any?
    private var appSwitchObserver: Any?

    private func installDismissWatchers() {
        // Clicks in other apps' windows close the shelf (global monitor only sees events outside Paste).
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, isVisible, modalDepth == 0, !CardDragger.shared.isDragging else { return }
            if NSMouseInRect(NSEvent.mouseLocation, panel.frame, false) || NSMouseInRect(NSEvent.mouseLocation, previewPanel.frame, false) && previewPanel.isVisible { return }
            hide()
        }
        // Switching to another app (⌘Tab, Dock, Mission Control) closes it too.
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, isVisible, modalDepth == 0 else { return }
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == Bundle.main.bundleIdentifier { return }
            if let target = model.targetApp, app?.processIdentifier == target.processIdentifier { return }
            hide()
        }
    }

    private func removeDismissWatchers() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
        if let o = appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        outsideClickMonitor = nil; appSwitchObserver = nil
    }

    // MARK: Preview window

    func updatePreview(frameOfCard: CGRect?) {
        guard let frame = frameOfCard, model.previewItem != nil, isVisible else { previewPanel.orderOut(nil); return }
        let size = NSSize(width: 640, height: 460)
        let screenFrame = panel.screen?.frame ?? panel.frame
        // Card frame comes in panel-content coordinates with origin at the top-left.
        let cardMidX = panel.frame.minX + frame.midX
        var x = cardMidX - size.width / 2
        x = max(screenFrame.minX + 12, min(x, screenFrame.maxX - size.width - 12))
        let y = panel.frame.maxY + 10
        previewPanel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        previewPanel.orderFront(nil)
    }

    // MARK: Keyboard

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.handleKey(e) }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            guard let self else { return e }
            let flag = AppSettings.shared.quickPasteModifier.flag
            let others = NSEvent.ModifierFlags([.command, .option, .control, .shift]).subtracting(flag)
            model.quickPasteHeld = e.modifierFlags.contains(flag) && e.modifierFlags.intersection(others).isEmpty
            return e
        }
    }

    private func removeMonitors() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil; flagsMonitor = nil
    }

    private var textFieldFocused: Bool { panel.firstResponder is NSTextView }

    /// A plain AppKit view used as the source of card drags. (SwiftUI's hosting view runs its own
    /// drag machinery and ignores a custom NSDraggingSource, which leaves drops with no allowed operation.)
    private lazy var dragSource: NSView = {
        let v = NSView(frame: panel.contentView?.bounds ?? .zero)
        v.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(v, positioned: .below, relativeTo: nil)
        return v
    }()
    var shelfView: NSView? { panel == nil ? nil : dragSource }

    /// Field editor of the shelf (the panel is key while Paste itself stays inactive, so NSApp.keyWindow is nil).
    var fieldEditor: NSTextView? { panel?.firstResponder as? NSTextView }

    private func handleKey(_ e: NSEvent) -> NSEvent? {
        guard e.window === panel || e.window === previewPanel else { return e }
        let settings = AppSettings.shared
        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = Int(e.keyCode)

        // Editors own the keyboard, except Escape.
        if model.editingItem != nil || model.renamingItem != nil || model.renamingPinboard != nil {
            if code == kVK_Escape {
                if model.editingItem != nil { model.finishEdit(save: nil) }
                model.renamingItem = nil; model.renamingPinboard = nil
                return nil
            }
            return e
        }

        if let s = settings.nextPinboardShortcut, s.matches(e) { model.cycleList(1); return nil }
        if let s = settings.prevPinboardShortcut, s.matches(e) { model.cycleList(-1); return nil }

        switch code {
        case kVK_Escape:
            if model.previewItem != nil { model.previewItem = nil }
            else if !model.query.isEmpty { model.query = "" }
            else if model.searchActive { model.endSearch() }
            else { hide() }
            return nil
        case kVK_LeftArrow, kVK_RightArrow:
            if textFieldFocused && mods.contains(.command) { return e }
            model.move(code == kVK_LeftArrow ? -1 : 1, extend: mods.contains(.shift))
            return nil
        case kVK_Home: model.selection = model.visibleItems.first.map { [$0.id] } ?? []; model.scrollTarget = model.selection.first; return nil
        case kVK_End: model.selection = model.visibleItems.last.map { [$0.id] } ?? []; model.scrollTarget = model.selection.first; return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            model.paste(plainText: mods.contains(settings.plainTextModifier.flag) ? true : nil)
            return nil
        case kVK_Space where !textFieldFocused || model.query.isEmpty:
            if mods.isEmpty { model.togglePreview(); return nil }
        case kVK_Delete, kVK_ForwardDelete:
            if textFieldFocused && !model.query.isEmpty { return e }
            if mods.isEmpty || mods == .command { model.delete(); return nil }
        case kVK_Tab:
            model.cycleList(mods.contains(.shift) ? -1 : 1); return nil
        default: break
        }

        // Quick paste: ⌘1…⌘9 (modifier configurable).
        if mods == settings.quickPasteModifier.flag,
           let ch = e.charactersIgnoringModifiers, let n = Int(ch), (1...9).contains(n) {
            model.quickPaste(n - 1); return nil
        }

        if mods == .command, let ch = e.charactersIgnoringModifiers?.lowercased() {
            switch ch {
            case "c": if textFieldFocused, (panel.firstResponder as? NSTextView)?.selectedRange().length ?? 0 > 0 { return e }
                model.copy(); return nil
            case "e": model.startEdit(); return nil
            case "r": model.startRename(); return nil
            case "d": if let id = model.selection.first, let n = ClipStore.shared.duplicate(id) { model.select(n) }; return nil
            case "n": model.newTextItem(); return nil
            case "f": model.activateSearch(); return nil
            case "a": if textFieldFocused { return e }; model.selectAll(); return nil
            case ",": hide(); AppDelegate.shared.openSettings(); return nil
            case "q": NSApp.terminate(nil); return nil
            case "w": hide(); return nil
            case "v": if textFieldFocused { return e }; return nil
            default: break
            }
        }
        if mods == [.command, .shift], e.charactersIgnoringModifiers?.lowercased() == "c" { model.copy(plainText: true); return nil }

        // Typing anything printable starts a search.
        if !textFieldFocused, mods.subtracting(.shift).isEmpty, let chars = e.characters, !chars.isEmpty,
           chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
           !(code == kVK_Space && model.query.isEmpty) {
            model.query += chars
            model.activateSearch()
            return nil
        }
        return e
    }
}
