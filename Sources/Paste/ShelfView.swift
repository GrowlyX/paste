import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Metrics {
    static let cardWidth: CGFloat = 232
    static let cardHeight: CGFloat = 229
    static let cardSpacing: CGFloat = 24
    static let cardRadius: CGFloat = 14
    static let headerHeight: CGFloat = 48
    static let topBarHeight: CGFloat = 60
    static let sideInset: CGFloat = 8
    static let bottomInset: CGFloat = 9
    static let panelRadius: CGFloat = 26
    static let selectionBlue = Color(red: 52 / 255, green: 120 / 255, blue: 246 / 255)
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

struct CardFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue()) { $1 } }
}

struct ShelfView: View {
    @EnvironmentObject var model: PanelModel
    @EnvironmentObject var store: ClipStore
    @Environment(\.colorScheme) var scheme
    @State private var cardFrames: [UUID: CGRect] = [:]

    var body: some View {
        ZStack {
            let shape = UnevenRoundedRectangle(topLeadingRadius: Metrics.panelRadius, bottomLeadingRadius: Metrics.panelRadius,
                                               bottomTrailingRadius: Metrics.panelRadius, topTrailingRadius: Metrics.panelRadius,
                                               style: .continuous)
            VisualEffect(material: scheme == .dark ? .hudWindow : .popover)
                .overlay(scheme == .dark ? Color(red: 0.2, green: 0.21, blue: 0.22).opacity(0.55) : Color.white.opacity(0.35))
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(scheme == .dark ? 0.16 : 0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 18, y: 4)

            VStack(spacing: 0) {
                TopBar().frame(height: Metrics.topBarHeight)
                CardStrip(cardFrames: $cardFrames)
                Spacer(minLength: 0)
            }
            .clipShape(shape)

            if model.editingItem != nil { EditorOverlay().transition(.opacity) }
        }
        .padding(.horizontal, Metrics.sideInset)
        .padding(.bottom, Metrics.bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onPreferenceChange(CardFrameKey.self) { cardFrames = $0; syncPreview() }
        .onChange(of: model.previewItem) { _ in syncPreview() }
        .onChange(of: model.selection) { _ in
            if model.previewItem != nil { model.previewItem = model.selection.first }
        }
    }

    private func syncPreview() {
        PanelController.shared.updatePreview(frameOfCard: model.previewItem.flatMap { cardFrames[$0] })
    }
}

// MARK: - Top bar

struct TopBar: View {
    @EnvironmentObject var model: PanelModel
    @EnvironmentObject var store: ClipStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var sync: SyncEngine

    var body: some View {
        ZStack {
            HStack(spacing: 12) {
                if let app = model.targetApp, let bid = app.bundleIdentifier {
                    Image(nsImage: AppIconCache.shared.icon(for: bid))
                        .resizable().frame(width: 30, height: 30)
                        .help("Items will be pasted to \(model.targetAppName)")
                }
                if settings.isPaused {
                    Label("Paused", systemImage: "pause.circle.fill")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                } else if settings.iCloudSync {
                    SyncIndicator()
                }
                Spacer()
                MoreMenu()
            }
            .padding(.horizontal, 20)

            HStack(spacing: 6) {
                if model.searchActive {
                    SearchField()
                    ForEach(model.allLists, id: \.self) { list in CompactTab(list: list) }
                } else {
                    Button { model.activateSearch() } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .regular))
                            .frame(width: 32, height: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).padding(.trailing, 10).help("Search (⌘F)")
                    ForEach(model.allLists, id: \.self) { list in ListTab(list: list) }
                    Button { model.newPinboard() } label: {
                        Image(systemName: "plus").font(.system(size: 17, weight: .regular))
                            .frame(width: 32, height: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).padding(.leading, 10).help("New Pinboard")
                }
            }
            .foregroundStyle(.primary)
        }
    }
}

struct SyncIndicator: View {
    @EnvironmentObject var sync: SyncEngine
    @State private var spin = false

    var body: some View {
        Button { SyncEngine.shared.pull(); SyncEngine.shared.push() } label: {
            Image(systemName: sync.status == .unavailable ? "icloud.slash" : "arrow.triangle.2.circlepath")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(spin ? 360 : 0))
        }
        .buttonStyle(.plain)
        .help("iCloud: " + (sync.statusText.isEmpty ? "Off" : sync.statusText))
        .onChange(of: sync.status) { s in
            if s == .syncing { withAnimation(.linear(duration: 0.8)) { spin.toggle() } }
        }
    }
}

struct ListTab: View {
    @EnvironmentObject var model: PanelModel
    @EnvironmentObject var store: ClipStore
    let list: ListSelection
    @State private var hover = false
    @State private var dropTarget = false
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    var board: Pinboard? { if case .pinboard(let id) = list { return store.pinboard(id) } else { return nil } }
    var selected: Bool { model.list == list }

    var body: some View {
        HStack(spacing: 7) {
            if let board {
                Circle().fill(board.color.color).frame(width: 12, height: 12)
                if model.renamingPinboard == board.id {
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.plain).font(.system(size: 14, weight: .medium))
                        .frame(width: max(60, CGFloat(draftName.count) * 8 + 16))
                        .focused($nameFocused)
                        .onSubmit(commitRename)
                        .onAppear { draftName = board.name; DispatchQueue.main.async { nameFocused = true } }
                        .onChange(of: nameFocused) { f in if !f { commitRename() } }
                } else {
                    Text(board.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    if board.isShared {
                        Image(systemName: "person.2.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                            .help("Shared pinboard")
                    }
                }
            } else {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 14, weight: .medium))
                Text("Clipboard").font(.system(size: 14, weight: .medium))
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(Capsule().fill(Color.primary.opacity(selected ? 0.13 : (hover || dropTarget ? 0.07 : 0))))
        .overlay(Capsule().strokeBorder(Metrics.selectionBlue, lineWidth: dropTarget ? 2 : 0))
        .contentShape(Capsule())
        .onHover { hover = $0 }
        .onTapGesture {
            if NSApp.currentEvent?.clickCount == 2, let board { model.renamingPinboard = board.id } else { model.list = list }
        }
        .onDrop(of: [.utf8PlainText, .plainText, .fileURL, .url, .image], isTargeted: $dropTarget, perform: handleDrop)
        .contextMenu { if let board { PinboardMenu(board: board) } }
    }

    private func commitRename() {
        guard let board, model.renamingPinboard == board.id else { return }
        let name = draftName.trimmingCharacters(in: .whitespaces)
        store.updatePinboard(board.id) { $0.name = name.isEmpty ? "Untitled" : name }
        model.renamingPinboard = nil
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let board else {
            model.draggingIDs = []
            return false
        }
        if !model.draggingIDs.isEmpty {
            model.pin(model.draggingIDs, to: board.id)
            model.draggingIDs = []
            return true
        }
        // External drop: create an item straight in this pinboard.
        for p in providers where p.canLoadObject(ofClass: NSString.self) {
            _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                guard let s = obj as? String else { return }
                DispatchQueue.main.async {
                    var item = ClipItem(kind: ClipboardMonitor.classify(text: s), text: s, contentHash: ClipStore.hash(s))
                    item.inHistory = false; item.pinboardID = board.id; item.pinnedAt = Date()
                    store.add(item)
                    if item.kind == .link { LinkPreviewer.shared.fetchIfNeeded(item.id) }
                }
            }
            return true
        }
        return false
    }
}

struct PinboardMenu: View {
    @EnvironmentObject var model: PanelModel
    @EnvironmentObject var store: ClipStore
    let board: Pinboard

    var body: some View {
        Button("Rename") { model.renamingPinboard = board.id }
        if board.isShared {
            let people = SharedPinboards.shared.participants[board.id] ?? []
            Text(people.isEmpty ? "Shared · waiting for others to join" : "Shared with " + people.joined(separator: ", "))
            Button("Show Shared Folder in Finder") { SharedPinboards.shared.revealFolder(board.id) }
            Button("Stop Sharing on This Mac") { SharedPinboards.shared.leave(board.id) }
        } else {
            Button("Share Pinboard…") { SharedPinboards.shared.share(board.id) }
        }
        Button("Delete…") { model.confirmDeletePinboard(board.id) }
        Divider()
        Picker("Color", selection: Binding(get: { board.color }, set: { c in store.updatePinboard(board.id) { $0.color = c } })) {
            ForEach(PinboardColor.allCases, id: \.self) { c in
                Image(nsImage: dotImage(c)).tag(c)
            }
        }
        .pickerStyle(.palette)
    }

    private func dotImage(_ c: PinboardColor) -> NSImage {
        let img = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
            NSColor(c.color).setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        img.isTemplate = false
        return img
    }
}

struct CompactTab: View {
    @EnvironmentObject var model: PanelModel
    @EnvironmentObject var store: ClipStore
    let list: ListSelection

    var body: some View {
        Button { model.list = list } label: {
            Group {
                if case .pinboard(let id) = list, let b = store.pinboard(id) {
                    Circle().fill(b.color.color).frame(width: 12, height: 12)
                } else {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 15, weight: .medium))
                }
            }
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.primary.opacity(model.list == list ? 0.13 : 0)))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help({ if case .pinboard(let id) = list { return store.pinboard(id)?.name ?? "" } else { return "Clipboard" } }())
    }
}

struct SearchField: View {
    @EnvironmentObject var model: PanelModel
    @FocusState private var focused: Bool
    @State private var showFilters = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(.secondary)
            TextField("Search", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            Button { showFilters.toggle() } label: {
                Image(systemName: model.filterKinds.isEmpty && model.filterApps.isEmpty
                      ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(model.filterKinds.isEmpty && model.filterApps.isEmpty ? Color.secondary : Metrics.selectionBlue)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showFilters, arrowEdge: .top) { FilterPopover().environmentObject(model) }
        }
        .padding(.horizontal, 12)
        .frame(width: 400, height: 34)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Metrics.selectionBlue.opacity(focused ? 0.85 : 0), lineWidth: 3).padding(-3))
        .padding(.trailing, 14)
        .onAppear { DispatchQueue.main.async { focused = true; moveCaretToEnd() } }
        .onChange(of: model.searchFocusRequest) { _ in focused = true; moveCaretToEnd() }
    }

    /// Focusing selects all text; put the caret after what was already typed so the next key appends.
    private func moveCaretToEnd(attempt: Int = 0) {
        DispatchQueue.main.async {
            if let tv = PanelController.shared.fieldEditor {
                tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            } else if attempt < 5 {
                moveCaretToEnd(attempt: attempt + 1)
            }
        }
    }
}

struct FilterPopover: View {
    @EnvironmentObject var model: PanelModel

    var apps: [(String, String)] {
        var seen = [String: String]()
        for i in ClipStore.shared.items { if let b = i.appBundleID { seen[b] = i.appName ?? b } }
        return seen.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Filters").font(.headline)
                Spacer()
                if !model.filterKinds.isEmpty || !model.filterApps.isEmpty {
                    Button("Reset") { model.filterKinds = []; model.filterApps = [] }.buttonStyle(.link)
                }
            }
            Text("Type").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            FlowChips(items: ItemKind.allCases.map { ($0.rawValue, $0.displayName, Image(systemName: $0.symbol)) },
                      isOn: { model.filterKinds.contains(ItemKind(rawValue: $0)!) },
                      toggle: { k in let kind = ItemKind(rawValue: k)!
                          if model.filterKinds.contains(kind) { model.filterKinds.remove(kind) } else { model.filterKinds.insert(kind) } })
            Text("App").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(apps, id: \.0) { bid, name in
                        Button {
                            if model.filterApps.contains(bid) { model.filterApps.remove(bid) } else { model.filterApps.insert(bid) }
                        } label: {
                            HStack {
                                Image(nsImage: AppIconCache.shared.icon(for: bid)).resizable().frame(width: 18, height: 18)
                                Text(name)
                                Spacer()
                                if model.filterApps.contains(bid) { Image(systemName: "checkmark").foregroundStyle(Metrics.selectionBlue) }
                            }
                            .padding(.vertical, 3).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 180)
        }
        .padding(14)
        .frame(width: 280)
    }
}

struct FlowChips: View {
    let items: [(String, String, Image)]
    let isOn: (String) -> Bool
    let toggle: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.0) { key, label, icon in
                Button { toggle(key) } label: {
                    HStack(spacing: 4) { icon; Text(label) }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 8).frame(height: 24)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(isOn(key) ? Metrics.selectionBlue : Color.primary.opacity(0.08)))
                        .foregroundStyle(isOn(key) ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct MoreMenu: View {
    @EnvironmentObject var model: PanelModel
    @EnvironmentObject var settings: AppSettings
    @State private var hover = false

    var body: some View {
        Menu {
            Button("About Paste") { PanelController.shared.hide(); AppDelegate.shared.showAbout() }
            Divider()
            Button("New Text Item") { model.newTextItem() }.keyboardShortcut("n")
            Button(PasteStack.shared.isActive ? "Close Paste Stack" : "Open Paste Stack") {
                PanelController.shared.hide(); PasteStack.shared.toggle()
            }
            Button("Join Shared Pinboard…") { SharedPinboards.shared.join() }
            Button("Settings…") { PanelController.shared.hide(); AppDelegate.shared.openSettings() }.keyboardShortcut(",")
            Divider()
            Menu("Help") {
                Button("Keyboard Shortcuts") { PanelController.shared.hide(); AppDelegate.shared.openSettings(tab: .shortcuts) }
                Button("Show Paste Data in Finder") {
                    PanelController.shared.hide(); NSWorkspace.shared.open(ClipStore.shared.baseDir)
                }
            }
            Divider()
            if settings.isPaused {
                Button("Resume Paste") { settings.pausedUntil = nil }
            } else {
                Menu("Pause Paste") {
                    Button("For 15 Minutes") { pause(15 * 60) }
                    Button("For 1 Hour") { pause(3600) }
                    Button("For 8 Hours") { pause(8 * 3600) }
                    Button("Until Tomorrow") { settings.pausedUntil = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400)) }
                    Button("Until Resumed") { settings.pausedUntil = .distantFuture }
                }
            }
            Button("Quit Paste") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(hover ? 0.1 : 0)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hover = $0 }
    }

    private func pause(_ seconds: TimeInterval) { settings.pausedUntil = Date().addingTimeInterval(seconds) }
}

// MARK: - Cards

struct CardStrip: View {
    @EnvironmentObject var model: PanelModel
    @Binding var cardFrames: [UUID: CGRect]

    var body: some View {
        let items = model.visibleItems
        Group {
            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: model.isFiltering ? "magnifyingglass" : (model.list == .history ? "clock" : "pin"))
                        .font(.system(size: 30, weight: .light))
                    Text(model.isFiltering ? "Nothing found" : (model.list == .history ? "History is empty" : "Pinboard is empty"))
                        .font(.system(size: 15, weight: .medium))
                    if !model.isFiltering && model.list != .history {
                        Text("Drag cards here or right-click a card and choose Pin.").font(.system(size: 12))
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: Metrics.cardHeight + 16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        TimelineView(.periodic(from: .now, by: 30)) { ctx in
                            HStack(spacing: 0) {
                                Color.clear.frame(width: 0, height: 1).id("start")
                                LazyHStack(spacing: Metrics.cardSpacing) {
                                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                                        CardView(item: item, index: idx, now: ctx.date)
                                            .id(item.id)
                                            .background(GeometryReader { g in
                                                Color.clear.preference(key: CardFrameKey.self, value: [item.id: g.frame(in: .global)])
                                            })
                                    }
                                }
                                .padding(.horizontal, Metrics.cardSpacing)
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .onChange(of: model.scrollTarget) { id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            if id == model.visibleItems.first?.id { proxy.scrollTo("start", anchor: .leading) } else { proxy.scrollTo(id) }
                        }
                    }
                    .onChange(of: model.scrollToStartRequest) { _ in proxy.scrollTo("start", anchor: .leading) }
                    .onAppear { proxy.scrollTo("start", anchor: .leading) }
                }
            }
        }
    }
}
