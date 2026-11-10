import AppKit
import CryptoKit
import SwiftUI

/// Everything that gets persisted (locally) and exchanged between Macs (via iCloud Drive).
struct LibrarySnapshot: Codable {
    var items: [ClipItem]
    var pinboards: [Pinboard]
    var itemTombstones: [UUID: Date] = [:]
    var pinboardTombstones: [UUID: Date] = [:]
    var deviceName: String?
    var savedAt = Date()
}

/// Owns all clipboard items and pinboards, persists them to Application Support.
final class ClipStore: ObservableObject {
    static let shared = ClipStore()

    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var pinboards: [Pinboard] = []
    private(set) var itemTombstones: [UUID: Date] = [:]
    private(set) var pinboardTombstones: [UUID: Date] = [:]

    let baseDir: URL
    let dataDir: URL
    private var saveWork: DispatchWorkItem?

    private init() {
        // PASTE_HOME points the app at another library, e.g. demo data for screenshots.
        if let home = ProcessInfo.processInfo.environment["PASTE_HOME"], !home.isEmpty {
            baseDir = URL(fileURLWithPath: (home as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            baseDir = support.appendingPathComponent("app.paste.clipboard", isDirectory: true)
        }
        dataDir = baseDir.appendingPathComponent("data", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        load()
    }

    private var dbURL: URL { baseDir.appendingPathComponent("library.json") }

    private func load() {
        if let data = try? Data(contentsOf: dbURL), let snap = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) {
            items = snap.items
            pinboards = snap.pinboards
            itemTombstones = snap.itemTombstones
            pinboardTombstones = snap.pinboardTombstones
        } else {
            seedWelcome()
        }
        prune()
    }

    private func seedWelcome() {
        pinboards = [Pinboard(name: "Useful Links", color: .red, sortIndex: 0),
                     Pinboard(name: "Snippets", color: .orange, sortIndex: 1)]
        let welcome: [(String, String)] = [
            ("Welcome", "Everything you copy lands here.\n\nPress ⇧⌘V anywhere to open this shelf, pick a card with the arrow keys and hit Return to drop it into the app you're using."),
            ("Find", "Just start typing to search everything you've copied.\n\nUse the filter button to narrow results by type or by the app it came from."),
            ("Pin", "Right-click a card and choose Pin, or drag it onto a pinboard tab.\n\nPinned cards stay put even when you erase your history."),
        ]
        let now = Date()
        items = welcome.enumerated().map { i, w in
            var item = ClipItem(kind: .text, text: w.1, contentHash: ClipStore.hash(w.1))
            item.title = w.0
            item.createdAt = now.addingTimeInterval(TimeInterval(-i))
            item.appBundleID = Bundle.main.bundleIdentifier
            item.appName = "Paste"
            return item
        }
        scheduleSave()
    }

    var sortedPinboards: [Pinboard] { pinboards.sorted { $0.sortIndex < $1.sortIndex } }

    // MARK: Queries

    func items(for list: ListSelection) -> [ClipItem] {
        switch list {
        case .history:
            return items.filter { $0.inHistory }.sorted { $0.createdAt > $1.createdAt }
        case .pinboard(let id):
            return items.filter { $0.pinboardID == id }.sorted { ($0.pinnedAt ?? $0.createdAt) > ($1.pinnedAt ?? $1.createdAt) }
        }
    }

    func item(_ id: UUID) -> ClipItem? { items.first { $0.id == id } }
    func pinboard(_ id: UUID) -> Pinboard? { pinboards.first { $0.id == id } }

    // MARK: Mutations

    /// Adds a freshly captured item, or bumps an identical existing one to the front. Returns the item's id.
    @discardableResult
    func add(_ new: ClipItem) -> UUID {
        var resultID = new.id
        if new.inHistory, let idx = items.firstIndex(where: { $0.contentHash == new.contentHash && $0.kind == new.kind }) {
            resultID = items[idx].id
            items[idx].createdAt = Date()
            items[idx].modifiedAt = Date()
            items[idx].inHistory = true
            items[idx].appBundleID = new.appBundleID ?? items[idx].appBundleID
            items[idx].appName = new.appName ?? items[idx].appName
            new.ownedFiles.forEach(removeDataFile)  // discard duplicate payload
        } else {
            items.append(new)
        }
        prune()
        scheduleSave()
        return resultID
    }

    func update(_ id: UUID, _ change: (inout ClipItem) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[idx])
        items[idx].modifiedAt = Date()
        scheduleSave()
    }

    /// Moves an item to the top of history (used after pasting it).
    func touch(_ id: UUID) {
        update(id) { $0.createdAt = Date(); $0.inHistory = true }
    }

    /// Removes an item from a given list; deletes it entirely when nothing references it.
    func remove(_ ids: Set<UUID>, from list: ListSelection) {
        for id in ids {
            guard let idx = items.firstIndex(where: { $0.id == id }) else { continue }
            switch list {
            case .history: items[idx].inHistory = false
            case .pinboard: items[idx].pinboardID = nil; items[idx].pinnedAt = nil
            }
            items[idx].modifiedAt = Date()
            if !items[idx].inHistory && items[idx].pinboardID == nil {
                let gone = items.remove(at: idx)
                itemTombstones[gone.id] = Date()
                gone.ownedFiles.forEach { removeDataFile($0); SyncEngine.shared.deleteCloudData($0) }
            }
        }
        scheduleSave()
    }

    func pin(_ ids: Set<UUID>, to board: UUID) {
        for id in ids { update(id) { $0.pinboardID = board; $0.pinnedAt = Date() } }
    }

    func duplicate(_ id: UUID) -> UUID? {
        guard var copy = item(id) else { return nil }
        copy.id = UUID()
        copy.createdAt = Date()
        copy.modifiedAt = Date()
        copy.contentHash += "-" + copy.id.uuidString
        // Copy owned files so the two items are independent.
        func dup(_ name: String?) -> String? {
            guard let name else { return nil }
            let newName = UUID().uuidString + "." + (name as NSString).pathExtension
            try? FileManager.default.copyItem(at: dataURL(name), to: dataURL(newName))
            return newName
        }
        copy.imageFile = dup(copy.imageFile); copy.rtfFile = dup(copy.rtfFile)
        copy.htmlFile = dup(copy.htmlFile); copy.linkImageFile = dup(copy.linkImageFile)
        items.append(copy)
        scheduleSave()
        return copy.id
    }

    func editText(_ id: UUID, to newText: String) {
        update(id) { item in
            item.text = newText
            item.contentHash = ClipStore.hash(newText)
            if let rtf = item.rtfFile { self.removeDataFile(rtf); item.rtfFile = nil }
            if let html = item.htmlFile { self.removeDataFile(html); item.htmlFile = nil }
            item.kind = ClipboardMonitor.classify(text: newText)
            item.linkPreviewFetched = false
        }
    }

    func eraseHistory() {
        remove(Set(items.filter { $0.inHistory }.map(\.id)), from: .history)
    }

    func addPinboard(name: String = "Untitled") -> Pinboard {
        let used = Set(pinboards.map(\.color))
        let color = PinboardColor.allCases.first { !used.contains($0) } ?? PinboardColor.allCases[pinboards.count % 8]
        let board = Pinboard(name: name, color: color, sortIndex: (pinboards.map(\.sortIndex).max() ?? -1) + 1)
        pinboards.append(board)
        scheduleSave()
        return board
    }

    func updatePinboard(_ id: UUID, _ change: (inout Pinboard) -> Void) {
        guard let idx = pinboards.firstIndex(where: { $0.id == id }) else { return }
        change(&pinboards[idx])
        pinboards[idx].modifiedAt = Date()
        scheduleSave()
    }

    /// Merges a collaborator's copy of a shared pinboard. Items stay scoped to that pinboard
    /// (no content de-duplication against personal history). Returns true when anything changed.
    @discardableResult
    func mergeShared(boardID: UUID, meta: Pinboard?, items remote: [ClipItem], tombstones: [UUID: Date]) -> Bool {
        var changed = false
        if let meta, let idx = pinboards.firstIndex(where: { $0.id == boardID }), pinboards[idx].modifiedAt < meta.modifiedAt {
            pinboards[idx].name = meta.name
            pinboards[idx].color = meta.color
            pinboards[idx].modifiedAt = meta.modifiedAt
            changed = true
        }
        for (id, date) in tombstones {
            guard let idx = items.firstIndex(where: { $0.id == id }), items[idx].pinboardID == boardID,
                  items[idx].modifiedAt <= date else { continue }
            if items[idx].inHistory {
                items[idx].pinboardID = nil; items[idx].pinnedAt = nil
            } else {
                items[idx].ownedFiles.forEach(removeDataFile)
                items.remove(at: idx)
            }
            changed = true
        }
        for var r in remote {
            if let t = tombstones[r.id], t >= r.modifiedAt { continue }
            r.pinboardID = boardID
            if let idx = items.firstIndex(where: { $0.id == r.id }) {
                guard items[idx].modifiedAt < r.modifiedAt else { continue }
                r.inHistory = items[idx].inHistory
                items[idx] = r
            } else {
                r.inHistory = false
                items.append(r)
            }
            changed = true
        }
        if changed { saveLocal(); SyncEngine.shared.push() }
        return changed
    }

    /// Adds a pinboard with a known id (joining a shared pinboard).
    func insertPinboard(_ board: Pinboard) {
        var b = board
        b.sortIndex = (pinboards.map(\.sortIndex).max() ?? -1) + 1
        pinboards.append(b)
        scheduleSave()
    }

    func deletePinboard(_ id: UUID) {
        remove(Set(items.filter { $0.pinboardID == id }.map(\.id)), from: .pinboard(id))
        pinboards.removeAll { $0.id == id }
        pinboardTombstones[id] = Date()
        scheduleSave()
    }

    /// Drops unpinned history items older than the retention window.
    func prune() {
        guard let interval = AppSettings.shared.retention.interval else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        let stale = items.filter { $0.inHistory && $0.createdAt < cutoff }.map(\.id)
        if !stale.isEmpty { remove(Set(stale), from: .history) }
        // Tombstones only need to outlive the time another Mac might be offline.
        let tombCutoff = Date().addingTimeInterval(-90 * 86_400)
        itemTombstones = itemTombstones.filter { $0.value > tombCutoff }
        pinboardTombstones = pinboardTombstones.filter { $0.value > tombCutoff }
    }

    func countOlderThanRetention(_ r: HistoryRetention) -> Int {
        guard let interval = r.interval else { return 0 }
        let cutoff = Date().addingTimeInterval(-interval)
        return items.filter { $0.inHistory && $0.pinboardID == nil && $0.createdAt < cutoff }.count
    }

    // MARK: Sync merge

    var snapshot: LibrarySnapshot {
        LibrarySnapshot(items: items, pinboards: pinboards, itemTombstones: itemTombstones,
                        pinboardTombstones: pinboardTombstones, deviceName: Host.current().localizedName)
    }

    /// Last-writer-wins merge of another Mac's snapshot. Returns true when anything changed.
    @discardableResult
    func merge(_ remote: LibrarySnapshot) -> Bool {
        var changed = false
        for (id, date) in remote.itemTombstones where (itemTombstones[id] ?? .distantPast) < date {
            itemTombstones[id] = date
            if let idx = items.firstIndex(where: { $0.id == id }), items[idx].modifiedAt <= date {
                items[idx].ownedFiles.forEach(removeDataFile)
                items.remove(at: idx); changed = true
            }
        }
        for (id, date) in remote.pinboardTombstones where (pinboardTombstones[id] ?? .distantPast) < date {
            pinboardTombstones[id] = date
            if let idx = pinboards.firstIndex(where: { $0.id == id }), pinboards[idx].modifiedAt <= date {
                pinboards.remove(at: idx); changed = true
            }
        }
        for r in remote.items {
            if let t = itemTombstones[r.id], t >= r.modifiedAt { continue }
            if let idx = items.firstIndex(where: { $0.id == r.id }) {
                if items[idx].modifiedAt < r.modifiedAt { items[idx] = r; changed = true }
            } else if let dupIdx = items.firstIndex(where: { $0.contentHash == r.contentHash && $0.kind == r.kind }) {
                // Same content captured independently on two Macs: keep the newer one.
                if items[dupIdx].modifiedAt < r.modifiedAt {
                    itemTombstones[items[dupIdx].id] = Date()
                    items[dupIdx] = r; changed = true
                }
            } else {
                items.append(r); changed = true
            }
        }
        for r in remote.pinboards {
            if let t = pinboardTombstones[r.id], t >= r.modifiedAt { continue }
            if let idx = pinboards.firstIndex(where: { $0.id == r.id }) {
                if pinboards[idx].modifiedAt < r.modifiedAt { pinboards[idx] = r; changed = true }
            } else {
                pinboards.append(r); changed = true
            }
        }
        if changed { saveLocal() }
        return changed
    }

    // MARK: Files

    func writeData(_ data: Data, ext: String) -> String {
        let name = UUID().uuidString + "." + ext
        try? data.write(to: dataURL(name))
        return name
    }

    func dataURL(_ name: String) -> URL { dataDir.appendingPathComponent(name) }

    func readData(_ name: String?) -> Data? {
        guard let name else { return nil }
        if let d = try? Data(contentsOf: dataURL(name)) { return d }
        return SyncEngine.shared.fetchCloudData(name) ?? SharedPinboards.shared.fetchData(name)
    }

    private func removeDataFile(_ name: String) {
        try? FileManager.default.removeItem(at: dataURL(name))
    }

    // MARK: Persistence

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveLocal()
            SyncEngine.shared.push()
            SharedPinboards.shared.pushAll()
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveLocal() {
        let snap = snapshot
        let url = dbURL
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(snap) { try? data.write(to: url, options: .atomic) }
        }
    }

    static func hash(_ s: String) -> String { hash(Data(s.utf8)) }
    static func hash(_ d: Data) -> String {
        SHA256.hash(data: d).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

extension ClipItem {
    var ownedFiles: [String] { [rtfFile, htmlFile, imageFile, linkImageFile].compactMap { $0 } }
}
