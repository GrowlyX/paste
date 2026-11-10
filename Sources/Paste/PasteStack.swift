import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftUI

/// Paste Stack: while it's open, everything you copy is collected in order, and each ⌘V in any app
/// pastes the next collected item. A ⌘V event tap swaps the pasteboard contents just before the
/// keystroke reaches the frontmost app.
final class PasteStack: NSObject, ObservableObject {
    static let shared = PasteStack()

    @Published private(set) var isActive = false
    @Published var itemIDs: [UUID] = []
    /// false = first copied is pasted first; true = last copied is pasted first.
    @Published var reversed = false { didSet { UserDefaults.standard.set(reversed, forKey: "pasteStackReversed") } }
    @Published private(set) var tapInstalled = false

    private var panel: NSPanel!
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?

    var items: [ClipItem] { itemIDs.compactMap { ClipStore.shared.item($0) } }
    var nextID: UUID? { reversed ? itemIDs.last : itemIDs.first }

    override init() {
        super.init()
        reversed = UserDefaults.standard.bool(forKey: "pasteStackReversed")
    }

    // MARK: Lifecycle

    func toggle() { isActive ? close() : open() }

    func open() {
        if panel == nil { makePanel() }
        position()
        panel.orderFrontRegardless()
        isActive = true
        installTap()
    }

    func close() {
        isActive = false
        panel?.orderOut(nil)
        removeTap()
        itemIDs = []
    }

    func clear() { itemIDs = [] }

    /// Called for every new clipboard capture.
    func collect(_ id: UUID) {
        guard isActive else { return }
        itemIDs.removeAll { $0 == id }
        itemIDs.append(id)
    }

    func add(_ ids: [UUID]) {
        if !isActive { open() }
        for id in ids where !itemIDs.contains(id) { itemIDs.append(id) }
    }

    func remove(_ id: UUID) { itemIDs.removeAll { $0 == id } }

    func move(from source: IndexSet, to destination: Int) { itemIDs.move(fromOffsets: source, toOffset: destination) }

    // MARK: Pasting

    /// Puts the next item on the pasteboard and drops it from the stack. Returns false when empty.
    @discardableResult
    func preparePasteNext() -> Bool {
        guard let id = nextID, let item = ClipStore.shared.item(id) else {
            if let id = nextID { remove(id) }  // item was deleted meanwhile
            return false
        }
        PasteService.write([item], plainText: AppSettings.shared.alwaysPlainText)
        remove(id)
        SoundFX.paste()
        return true
    }

    /// Pastes one specific item into the frontmost app (click in the stack window).
    func paste(_ id: UUID) {
        guard let item = ClipStore.shared.item(id) else { return }
        PasteService.write([item], plainText: AppSettings.shared.alwaysPlainText)
        remove(id)
        SoundFX.paste()
        if PasteService.hasAccessibility { pauseTapAndSendPaste() }
    }

    /// Pastes every remaining item at once, one per line, in stack order.
    func pasteAll() {
        let ordered = reversed ? items.reversed() : items
        guard !ordered.isEmpty else { return }
        PasteService.write(Array(ordered), plainText: AppSettings.shared.alwaysPlainText)
        itemIDs = []
        SoundFX.paste()
        if PasteService.hasAccessibility { pauseTapAndSendPaste() }
    }

    private func pauseTapAndSendPaste() {
        // Our own synthetic ⌘V must not pop another item.
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            PasteService.sendPasteKeystroke()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { if let t = self.tap, self.isActive { CGEvent.tapEnable(tap: t, enable: true) } }
        }
    }

    // MARK: ⌘V event tap

    private func installTap() {
        guard tap == nil else { return }
        guard PasteService.hasAccessibility else {
            PasteService.requestAccessibility()
            tapInstalled = false
            return
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<PasteStack>.fromOpaque(refcon!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard type == .keyDown, me.isActive, !me.itemIDs.isEmpty else { return Unmanaged.passUnretained(event) }
            let flags = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            guard key == Int64(kVK_ANSI_V), flags == .maskCommand,
                  event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                  NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return Unmanaged.passUnretained(event) }
            // Runs on the main run loop before the event is delivered, so the target app reads the new contents.
            me.preparePasteNext()
            return Unmanaged.passUnretained(event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: callback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            tapInstalled = false
            return
        }
        tap = t
        tapSource = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        tapInstalled = true
    }

    private func removeTap() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; tapSource = nil; tapInstalled = false
    }

    /// Retry once permission is granted (the stack window shows a button for this).
    func retryTap() { installTap() }

    // MARK: Window

    private func makePanel() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 520),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.sharingType = AppSettings.shared.showDuringScreenSharing ? .readOnly : .none
        panel.contentView = NSHostingView(rootView: PasteStackView().environmentObject(self).environmentObject(ClipStore.shared))
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
        let vf = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: vf.maxX - panel.frame.width - 16, y: vf.midY - panel.frame.height / 2))
    }

    func applySharing() { panel?.sharingType = AppSettings.shared.showDuringScreenSharing ? .readOnly : .none }
}

// MARK: - View

struct PasteStackView: View {
    @EnvironmentObject var stack: PasteStack
    @EnvironmentObject var store: ClipStore
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Metrics.selectionBlue)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Paste Stack").font(.system(size: 14, weight: .semibold))
                    Text(stack.itemIDs.isEmpty ? "Empty" : "\(stack.itemIDs.count) item\(stack.itemIDs.count == 1 ? "" : "s")")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                iconButton(stack.reversed ? "arrow.up" : "arrow.down",
                           help: stack.reversed ? "Pasting newest first" : "Pasting oldest first") { stack.reversed.toggle() }
                iconButton("trash", help: "Clear stack") { stack.clear() }.disabled(stack.itemIDs.isEmpty)
                iconButton("xmark", help: "Close Paste Stack") { stack.close() }
            }
            .padding(.horizontal, 14).frame(height: 52)

            Divider()

            if stack.itemIDs.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "square.stack.3d.up").font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
                    Text("Copy a few things").font(.system(size: 14, weight: .medium))
                    Text("Each copy lands here in order. Press ⌘V in any app to paste them one after another.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .padding(.horizontal, 26)
                    Spacer()
                }
            } else {
                List {
                    ForEach(Array(stack.items.enumerated()), id: \.element.id) { idx, item in
                        StackRow(item: item, position: displayPosition(idx), isNext: item.id == stack.nextID)
                            .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .onTapGesture(count: 2) { stack.paste(item.id) }
                            .contextMenu {
                                Button("Paste Now") { stack.paste(item.id) }
                                Button("Copy") { PasteService.write([item], plainText: false); SoundFX.copy() }
                                Divider()
                                Button("Remove from Stack") { stack.remove(item.id) }
                            }
                    }
                    .onMove { stack.move(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            Divider()

            VStack(spacing: 8) {
                if !stack.tapInstalled {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Allow Accessibility so ⌘V pastes from the stack.").font(.system(size: 11))
                        Spacer(minLength: 0)
                        Button("Retry") { stack.retryTap() }.controlSize(.small)
                    }
                }
                HStack {
                    Text("⌘V pastes the next item").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Paste All") { stack.pasteAll() }
                        .controlSize(.small)
                        .disabled(stack.itemIDs.isEmpty)
                }
            }
            .padding(12)
        }
        .frame(width: 300, height: 520)
        .background(VisualEffect(material: scheme == .dark ? .hudWindow : .popover))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(scheme == .dark ? 0.14 : 0.5)))
        .onDrop(of: [.utf8PlainText, .plainText], isTargeted: nil) { _ in
            let ids = PanelModel.shared.draggingIDs
            PanelModel.shared.draggingIDs = []
            guard !ids.isEmpty else { return false }
            stack.add(ids)
            return true
        }
    }

    /// Number shown on each row = paste order (1 pastes next).
    private func displayPosition(_ idx: Int) -> Int { stack.reversed ? stack.itemIDs.count - idx : idx + 1 }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct StackRow: View {
    @Environment(\.colorScheme) var scheme
    let item: ClipItem
    let position: Int
    let isNext: Bool

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                AppIconCache.shared.color(for: item.appBundleID)
                Text("\(position)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
            }
            .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(nsImage: AppIconCache.shared.icon(for: item.appBundleID)).resizable().frame(width: 14, height: 14)
                    Text(item.displayTitle).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if isNext {
                        Text("NEXT").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Metrics.selectionBlue))
                    }
                }
                preview
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(scheme == .dark ? Color(white: 20 / 255) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Metrics.selectionBlue, lineWidth: isNext ? 2.5 : 0))
    }

    @ViewBuilder private var preview: some View {
        switch item.kind {
        case .image:
            if let img = ImageCache.shared.image(item.imageFile) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        case .file:
            Text((item.fileURLs ?? []).map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))
                .font(.system(size: 12)).lineLimit(2)
        case .link:
            Text(item.linkTitle ?? item.text ?? "").font(.system(size: 12, weight: .medium)).lineLimit(1)
            Text(item.text ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        case .color:
            HStack {
                RoundedRectangle(cornerRadius: 4).fill(Color(hex: item.text ?? "") ?? .gray).frame(width: 22, height: 16)
                Text(item.text ?? "").font(.system(size: 12, weight: .medium))
            }
        case .text:
            Text(item.text ?? "").font(.system(size: 12)).lineLimit(3)
        }
    }
}
