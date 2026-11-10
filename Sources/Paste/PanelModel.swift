import AppKit
import Combine
import SwiftUI

/// View state for the shelf panel and all actions that operate on items.
final class PanelModel: ObservableObject {
    static let shared = PanelModel()

    @Published var list: ListSelection = .history { didSet { if oldValue != list { resetSelection() } } }
    @Published var query = "" { didSet { if oldValue != query { resetSelection() } } }
    @Published var searchActive = false
    @Published var searchFocusRequest = 0
    @Published var filterKinds: Set<ItemKind> = [] { didSet { resetSelection() } }
    @Published var filterApps: Set<String> = [] { didSet { resetSelection() } }

    @Published var selection: [UUID] = []
    @Published var scrollTarget: UUID?
    @Published var scrollToStartRequest = 0
    @Published var renamingItem: UUID?
    @Published var editingItem: UUID?
    @Published var editingIsNew = false
    @Published var renamingPinboard: UUID?
    @Published var previewItem: UUID?
    @Published var quickPasteHeld = false
    @Published var isKey = true
    @Published var targetApp: NSRunningApplication?

    private var bag = Set<AnyCancellable>()

    private init() {
        // Re-publish when the store changes so derived lists refresh.
        ClipStore.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send(); self?.validateSelection() }
        }.store(in: &bag)
    }

    var store: ClipStore { .shared }
    var isFiltering: Bool { !query.isEmpty || !filterKinds.isEmpty || !filterApps.isEmpty }
    var anyOverlay: Bool { renamingItem != nil || editingItem != nil || renamingPinboard != nil }

    var visibleItems: [ClipItem] {
        var result = store.items(for: list)
        if !filterKinds.isEmpty { result = result.filter { filterKinds.contains($0.kind) } }
        if !filterApps.isEmpty { result = result.filter { filterApps.contains($0.appBundleID ?? "") } }
        let terms = query.lowercased().split(separator: " ").map(String.init)
        if !terms.isEmpty {
            result = result.filter { item in
                let hay = item.searchableText.lowercased()
                return terms.allSatisfy { hay.contains($0) }
            }
        }
        return result
    }

    var selectedItems: [ClipItem] {
        let vis = visibleItems
        return selection.compactMap { id in vis.first { $0.id == id } }
    }

    var targetAppName: String { targetApp?.localizedName ?? "Active App" }

    // MARK: Selection

    func resetSelection() {
        let first = visibleItems.first?.id
        selection = first.map { [$0] } ?? []
        scrollTarget = first
        scrollToStartRequest += 1
    }

    private func validateSelection() {
        let ids = Set(visibleItems.map(\.id))
        let kept = selection.filter { ids.contains($0) }
        if kept != selection { selection = kept.isEmpty ? (visibleItems.first.map { [$0.id] } ?? []) : kept }
    }

    func select(_ id: UUID, extend: Bool = false, toggle: Bool = false) {
        if toggle {
            if let i = selection.firstIndex(of: id) { if selection.count > 1 { selection.remove(at: i) } } else { selection.append(id) }
        } else if extend, let anchor = selection.first {
            let vis = visibleItems.map(\.id)
            if let a = vis.firstIndex(of: anchor), let b = vis.firstIndex(of: id) {
                selection = a <= b ? Array(vis[a...b]) : Array(vis[b...a].reversed())
            }
        } else {
            selection = [id]
        }
        scrollTarget = id
    }

    func move(_ delta: Int, extend: Bool = false) {
        let vis = visibleItems.map(\.id)
        guard !vis.isEmpty else { return }
        let current = selection.last.flatMap { vis.firstIndex(of: $0) } ?? -1
        let next = max(0, min(vis.count - 1, current + delta))
        if extend, !selection.isEmpty {
            if let idx = selection.firstIndex(of: vis[next]) {
                selection.removeSubrange((idx + 1)...)
            } else {
                selection.append(vis[next])
            }
        } else {
            selection = [vis[next]]
        }
        scrollTarget = vis[next]
    }

    func selectAll() { selection = visibleItems.map(\.id) }

    // MARK: Lists

    var allLists: [ListSelection] { [.history] + store.sortedPinboards.map { .pinboard($0.id) } }

    func cycleList(_ delta: Int) {
        let lists = allLists
        guard let idx = lists.firstIndex(of: list) else { list = .history; return }
        list = lists[(idx + delta + lists.count) % lists.count]
    }

    func activateSearch() {
        searchActive = true
        searchFocusRequest += 1
    }

    func endSearch() {
        query = ""
        filterKinds = []
        filterApps = []
        searchActive = false
    }

    // MARK: Actions

    func paste(_ ids: [UUID]? = nil, plainText: Bool? = nil) {
        let items = (ids ?? selection).compactMap { store.item($0) }
        guard !items.isEmpty else { return }
        let plain = plainText ?? AppSettings.shared.alwaysPlainText
        let target = targetApp
        PasteService.write(items, plainText: plain)
        SoundFX.paste()
        if list == .history, items.count == 1 { store.touch(items[0].id) }
        PanelController.shared.hide(animated: false)

        guard AppSettings.shared.pasteDestination == .activeApp else { return }
        guard PasteService.hasAccessibility else {
            PasteService.requestAccessibility()
            return  // content stays on the clipboard so the user can paste manually
        }
        let needsActivation = NSApp.isActive
        if needsActivation { target?.activate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + (needsActivation ? 0.25 : 0.06)) {
            PasteService.sendPasteKeystroke()
        }
    }

    func copy(_ ids: [UUID]? = nil, plainText: Bool = false) {
        let items = (ids ?? selection).compactMap { store.item($0) }
        guard !items.isEmpty else { return }
        PasteService.write(items, plainText: plainText)
        SoundFX.copy()
        PanelController.shared.hide()
    }

    func quickPaste(_ n: Int) {
        let vis = visibleItems
        guard vis.indices.contains(n) else { return }
        paste([vis[n].id])
    }

    func delete(_ ids: [UUID]? = nil) {
        let targets = ids ?? selection
        guard !targets.isEmpty else { return }
        let vis = visibleItems.map(\.id)
        let lastIdx = targets.compactMap { vis.firstIndex(of: $0) }.max() ?? 0
        let remaining = vis.filter { !targets.contains($0) }
        let nextID = vis.dropFirst(lastIdx + 1).first { !targets.contains($0) } ?? remaining.last
        store.remove(Set(targets), from: list)
        selection = nextID.map { [$0] } ?? []
        scrollTarget = nextID
    }

    func pin(_ ids: [UUID]? = nil, to board: UUID) {
        store.pin(Set(ids ?? selection), to: board)
    }

    func pinToNewPinboard(_ ids: [UUID]? = nil) {
        let board = store.addPinboard()
        store.pin(Set(ids ?? selection), to: board.id)
        renamingPinboard = board.id
    }

    func newPinboard() {
        let board = store.addPinboard()
        list = .pinboard(board.id)
        renamingPinboard = board.id
    }

    func newTextItem() {
        var item = ClipItem(kind: .text, text: "", contentHash: UUID().uuidString)
        item.appBundleID = Bundle.main.bundleIdentifier
        item.appName = "Paste"
        if case .pinboard(let id) = list { item.pinboardID = id; item.pinnedAt = Date(); item.inHistory = false }
        store.add(item)
        endSearch()
        select(item.id)
        editingIsNew = true
        editingItem = item.id
    }

    func startEdit(_ id: UUID? = nil) {
        guard let id = id ?? selection.first, let item = store.item(id), [.text, .link, .color].contains(item.kind) else { return }
        editingIsNew = false
        editingItem = id
    }

    func finishEdit(save text: String?) {
        guard let id = editingItem else { return }
        if let text, !text.isEmpty {
            store.editText(id, to: text)
            if store.item(id)?.kind == .link { LinkPreviewer.shared.fetchIfNeeded(id) }
        } else if editingIsNew {
            store.remove([id], from: list)
        }
        editingItem = nil
        editingIsNew = false
    }

    func startRename(_ id: UUID? = nil) {
        guard let id = id ?? selection.first else { return }
        renamingItem = id
    }

    func togglePreview() {
        if previewItem != nil { previewItem = nil } else { previewItem = selection.first }
    }

    func share(_ id: UUID, via service: NSSharingService) {
        guard let item = store.item(id) else { return }
        service.perform(withItems: shareItems(item))
    }

    func shareItems(_ item: ClipItem) -> [Any] {
        switch item.kind {
        case .image: return item.imageFile.map { [store.dataURL($0)] } ?? []
        case .file: return (item.fileURLs ?? []).map { URL(fileURLWithPath: $0) }
        case .link: return [URL(string: item.text ?? "") as Any].compactMap { $0 }
        default: return [item.text ?? ""]
        }
    }

    func open(_ id: UUID) {
        guard let item = store.item(id) else { return }
        PanelController.shared.hide()
        switch item.kind {
        case .link: if let u = URL(string: item.text ?? "") { NSWorkspace.shared.open(u) }
        case .file: (item.fileURLs ?? []).forEach { NSWorkspace.shared.open(URL(fileURLWithPath: $0)) }
        case .image: if let f = item.imageFile { NSWorkspace.shared.open(store.dataURL(f)) }
        default: break
        }
    }

    func revealInFinder(_ id: UUID) {
        guard let item = store.item(id), let paths = item.fileURLs else { return }
        PanelController.shared.hide()
        NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
    }

    func confirmDeletePinboard(_ id: UUID) {
        guard let board = store.pinboard(id) else { return }
        let ok = PanelController.shared.runModal {
            let alert = NSAlert()
            alert.messageText = "Delete “\(board.name)”?"
            alert.informativeText = board.isShared
                ? "It's removed from this Mac and you stop syncing it. People you shared it with keep their copy."
                : "This pinboard and everything pinned to it will be removed. This can't be undone."
            alert.addButton(withTitle: "Delete").hasDestructiveAction = true
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }
        if ok {
            if board.isShared { SharedPinboards.shared.leave(id) }
            if list == .pinboard(id) { list = .history }
            store.deletePinboard(id)
        }
    }

    /// Items currently being dragged out of the shelf (so dropping on a tab pins them).
    var draggingIDs: [UUID] = []
}
