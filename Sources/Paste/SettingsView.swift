import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, privacy, shortcuts
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .privacy: "hand.raised"
        case .shortcuts: "keyboard"
        }
    }
}

final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    @ObservedObject var router = SettingsRouter.shared

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    Button { router.tab = tab } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 15))
                                .foregroundStyle(router.tab == tab ? Color.white : Metrics.selectionBlue)
                                .frame(width: 22)
                            Text(tab.title).font(.system(size: 13, weight: router.tab == tab ? .semibold : .regular))
                            Spacer()
                        }
                        .padding(.horizontal, 10).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(router.tab == tab ? Metrics.selectionBlue : .clear))
                        .foregroundStyle(router.tab == tab ? Color.white : Color.primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("Version " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 10).padding(.bottom, 12)
            }
            .padding(.horizontal, 10)
            .padding(.top, 52)
            .frame(width: 200)
            .background(VisualEffect(material: .sidebar))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(router.tab.title).font(.system(size: 15, weight: .semibold)).padding(.bottom, 14)
                    switch router.tab {
                    case .general: GeneralPane()
                    case .privacy: PrivacyPane()
                    case .shortcuts: ShortcutsPane()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 640, height: 620)
        .ignoresSafeArea()
    }
}

/// Rounded grouped box like System Settings.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
            .padding(.bottom, 22)
    }
}

struct Row<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var divider = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: subtitle == nil ? .center : .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13))
                    if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 16)
                trailing
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            if divider { Divider().padding(.leading, 12) }
        }
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary) }
        }
        .padding(.bottom, 8)
    }
}

struct GeneralPane: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var sync: SyncEngine

    var body: some View {
        SettingsGroup {
            Row(title: "Open at login") { Toggle("", isOn: $settings.openAtLogin).toggleStyle(.switch).labelsHidden() }
            Row(title: "iCloud sync",
                subtitle: sync.isAvailable ? "Sync history and pinboards with your other Macs through iCloud Drive." : "Sign in to iCloud and turn on iCloud Drive to sync.") {
                HStack(spacing: 10) {
                    if settings.iCloudSync && sync.isAvailable { Text(sync.statusText).font(.system(size: 12)).foregroundStyle(.secondary) }
                    Toggle("", isOn: Binding(get: { settings.iCloudSync && sync.isAvailable }, set: { settings.iCloudSync = $0 }))
                        .toggleStyle(.switch).labelsHidden().disabled(!sync.isAvailable)
                }
            }
            Row(title: "Sound effects") { Toggle("", isOn: $settings.soundEffects).toggleStyle(.switch).labelsHidden() }
            Row(title: "Show in menu bar", divider: false) {
                Toggle("", isOn: $settings.showInMenuBar).toggleStyle(.switch).labelsHidden()
                    .onChange(of: settings.showInMenuBar) { _ in AppDelegate.shared.updateStatusItem() }
            }
        }

        SectionTitle(title: "Paste Items")
        SettingsGroup {
            VStack(alignment: .leading, spacing: 14) {
                RadioRow(title: "To active app", subtitle: "Send the chosen item straight into the app you're working in.",
                         on: settings.pasteDestination == .activeApp) { settings.pasteDestination = .activeApp }
                if settings.pasteDestination == .activeApp && !PasteService.hasAccessibility {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Needs Accessibility access to type ⌘V for you.").font(.system(size: 12))
                        Button("Allow…") { PasteService.requestAccessibility() }.controlSize(.small)
                    }
                    .padding(.leading, 26)
                }
                RadioRow(title: "To clipboard", subtitle: "Only copy the item to the system clipboard so you can paste it yourself.",
                         on: settings.pasteDestination == .clipboard) { settings.pasteDestination = .clipboard }
            }
            .padding(12)
            Divider().padding(.leading, 12)
            Toggle("Always paste as Plain Text", isOn: $settings.alwaysPlainText)
                .toggleStyle(.checkbox).font(.system(size: 13)).padding(12)
        }

        SectionTitle(title: "Keep History")
        SettingsGroup {
            RetentionSlider().padding(12)
            Divider().padding(.leading, 12)
            HStack {
                Spacer()
                Button("Erase History…") { confirmErase() }
            }
            .padding(12)
        }
    }

    private func confirmErase() {
        let alert = NSAlert()
        alert.messageText = "Erase your clipboard history?"
        alert.informativeText = "Pinned items and pinboards are kept. This can't be undone."
        alert.addButton(withTitle: "Erase").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { ClipStore.shared.eraseHistory() }
    }
}

struct RadioRow: View {
    let title: String
    let subtitle: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle().fill(on ? Metrics.selectionBlue : Color.primary.opacity(0.1)).frame(width: 16, height: 16)
                    if on { Circle().fill(.white).frame(width: 6, height: 6) }
                }
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct RetentionSlider: View {
    @EnvironmentObject var settings: AppSettings
    @State private var value: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            Slider(value: $value, in: 0...4, step: 1) { editing in
                if !editing { apply() }
            }
            HStack {
                ForEach(HistoryRetention.allCases, id: \.self) { r in
                    Text(r.label).font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: r == .day ? .leading : (r == .forever ? .trailing : .center))
                }
            }
        }
        .onAppear { value = Double(settings.retention.rawValue) }
    }

    private func apply() {
        let r = HistoryRetention(rawValue: Int(value)) ?? .month
        guard r != settings.retention else { return }
        let older = ClipStore.shared.countOlderThanRetention(r)
        if older > 0 {
            let alert = NSAlert()
            alert.messageText = "Delete \(older) older item\(older == 1 ? "" : "s")?"
            alert.informativeText = "Some history is older than the new limit and will be removed. Pinned items are kept."
            alert.addButton(withTitle: "Delete").hasDestructiveAction = true
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { value = Double(settings.retention.rawValue); return }
        }
        settings.retention = r
        ClipStore.shared.prune()
    }
}

struct PrivacyPane: View {
    @EnvironmentObject var settings: AppSettings
    @State private var selectedApp: String?

    var body: some View {
        SettingsGroup {
            Row(title: "Show during screen sharing", subtitle: "Let other people see Paste when you share your screen.") {
                Toggle("", isOn: $settings.showDuringScreenSharing).toggleStyle(.switch).labelsHidden()
                    .onChange(of: settings.showDuringScreenSharing) { _ in PanelController.shared.applySharing() }
            }
            Row(title: "Generate link previews", subtitle: "Fetch page titles and images for copied links. Visiting a link can trigger one-time or tracking URLs.", divider: false) {
                Toggle("", isOn: $settings.linkPreviews).toggleStyle(.switch).labelsHidden()
            }
        }
        SettingsGroup {
            Row(title: "Ignore confidential content", subtitle: "Skip passwords and other data apps mark as concealed.") {
                Toggle("", isOn: $settings.ignoreConfidential).toggleStyle(.switch).labelsHidden()
            }
            Row(title: "Ignore transient content", subtitle: "Skip temporary data that apps put on the clipboard automatically.", divider: false) {
                Toggle("", isOn: $settings.ignoreTransient).toggleStyle(.switch).labelsHidden()
            }
        }

        SectionTitle(title: "Ignore Applications", subtitle: "Anything copied in these apps is never saved.")
        SettingsGroup {
            if settings.ignoredApps.isEmpty {
                Text("No apps").foregroundStyle(.secondary).font(.system(size: 13)).frame(maxWidth: .infinity).padding(16)
            }
            ForEach(settings.ignoredApps, id: \.self) { bid in
                HStack(spacing: 10) {
                    Image(nsImage: AppIconCache.shared.icon(for: bid)).resizable().frame(width: 26, height: 26)
                    Text(appName(bid)).font(.system(size: 13))
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(selectedApp == bid ? Metrics.selectionBlue.opacity(0.25) : .clear)
                .contentShape(Rectangle())
                .onTapGesture { selectedApp = bid }
                Divider().padding(.leading, 46)
            }
            HStack(spacing: 0) {
                Button { addApp() } label: { Image(systemName: "plus").frame(width: 26, height: 22) }
                Divider().frame(height: 16)
                Button {
                    if let s = selectedApp { settings.ignoredApps.removeAll { $0 == s }; selectedApp = nil }
                } label: { Image(systemName: "minus").frame(width: 26, height: 22) }
                .disabled(selectedApp == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(4)
            .background(Color.primary.opacity(0.03))
        }
    }

    private func appName(_ bid: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bid
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bid = Bundle(url: url)?.bundleIdentifier, !settings.ignoredApps.contains(bid) { settings.ignoredApps.append(bid) }
        }
    }
}

struct ShortcutsPane: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        SettingsGroup {
            Row(title: "Activate Paste") {
                ShortcutField(shortcut: $settings.activateShortcut)
                    .onChange(of: settings.activateShortcut) { _ in AppDelegate.shared.registerHotKey() }
            }
            Row(title: "Activate Paste Stack", divider: false) {
                ShortcutField(shortcut: $settings.pasteStackShortcut)
                    .onChange(of: settings.pasteStackShortcut) { _ in AppDelegate.shared.registerHotKey() }
            }
            if let failed = AppDelegate.shared.failedShortcuts.first {
                Text("\(failed) is already used by another app. Pick a different shortcut or quit that app.")
                    .font(.system(size: 12)).foregroundStyle(.orange).padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
        SettingsGroup {
            Row(title: "Show next pinboard") { ShortcutField(shortcut: $settings.nextPinboardShortcut) }
            Row(title: "Show previous pinboard", divider: false) { ShortcutField(shortcut: $settings.prevPinboardShortcut) }
        }
        SettingsGroup {
            Row(title: "Quick Paste") {
                HStack(spacing: 6) {
                    Picker("", selection: $settings.quickPasteModifier) {
                        ForEach(ModifierChoice.allCases) { Text($0.label).tag($0) }
                    }.labelsHidden().fixedSize()
                    Text("+ 1…9").font(.system(size: 13))
                }
            }
            Row(title: "Plain Text mode", subtitle: "Hold while pressing Return to paste without formatting.", divider: false) {
                Picker("", selection: $settings.plainTextModifier) {
                    ForEach(ModifierChoice.allCases) { Text($0.label).tag($0) }
                }.labelsHidden().fixedSize()
            }
        }

        SectionTitle(title: "In the shelf")
        SettingsGroup {
            ForEach(Array(cheatSheet.enumerated()), id: \.offset) { i, pair in
                Row(title: pair.0, divider: i < cheatSheet.count - 1) {
                    Text(pair.1).font(.system(size: 12, design: .rounded)).foregroundStyle(.secondary)
                }
            }
        }

        HStack {
            Spacer()
            Button("Reset shortcuts to default…") {
                let alert = NSAlert()
                alert.messageText = "Reset all shortcuts to their defaults?"
                alert.addButton(withTitle: "Reset"); alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn { settings.resetShortcuts(); AppDelegate.shared.registerHotKey() }
            }
        }
    }

    private var cheatSheet: [(String, String)] {
        [("Paste selected item", "↩"), ("Paste as plain text", "⇧↩"), ("Move between cards", "← →"),
         ("Extend selection", "⇧← ⇧→"), ("Preview", "Space"), ("Search", "Start typing or ⌘F"),
         ("Copy", "⌘C"), ("Edit text", "⌘E"), ("Rename", "⌘R"), ("Duplicate", "⌘D"), ("Delete", "⌫"),
         ("New text item", "⌘N"), ("Switch list", "⇥ or ⌘← ⌘→"), ("Close", "Esc")]
    }
}

// MARK: - Shortcut recorder

struct ShortcutField: View {
    @Binding var shortcut: Shortcut?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Type shortcut…" : (shortcut?.display ?? "Record Shortcut"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(recording ? Metrics.selectionBlue : (shortcut == nil ? .secondary : .primary))
                    .frame(width: 120, height: 24)
            }
            .buttonStyle(.plain)
            if shortcut != nil && !recording {
                Button { shortcut = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Metrics.selectionBlue, lineWidth: recording ? 2 : 0))
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        AppDelegate.shared.suspendHotKey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil }  // Escape cancels
            let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
            let isFunctionKey = (122...135).contains(Int(e.keyCode)) || [96, 97, 98, 99, 100, 101, 103, 105, 107, 109, 111, 113].contains(Int(e.keyCode))
            guard !mods.isEmpty || isFunctionKey else { NSSound.beep(); return nil }
            shortcut = Shortcut(keyCode: UInt32(e.keyCode), modifiers: mods.rawValue)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        AppDelegate.shared.registerHotKey()
    }
}
