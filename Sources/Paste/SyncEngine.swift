import AppKit

/// Syncs the library between Macs through iCloud Drive.
///
/// Layout in iCloud Drive (`~/Library/Mobile Documents/com~apple~CloudDocs/Paste/`):
///   devices/<deviceID>.json  – each Mac's full snapshot, written only by that Mac
///   data/<uuid>.<ext>        – shared payload files (images, RTF, link previews)
///
/// Every Mac writes only its own snapshot, so iCloud never sees write conflicts.
/// Each Mac merges the others' snapshots with per-record last-writer-wins plus tombstones.
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    enum Status: Equatable {
        case off, unavailable, syncing, synced(Date), error(String)
    }

    @Published private(set) var status: Status = .off

    private let fm = FileManager.default
    private var timer: Timer?
    private var seen: [String: Date] = [:]  // remote snapshot file -> modification date merged
    private let io = DispatchQueue(label: "paste.sync", qos: .utility)

    let iCloudDriveRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    var root: URL { iCloudDriveRoot.appendingPathComponent("Paste", isDirectory: true) }
    private var devicesDir: URL { root.appendingPathComponent("devices", isDirectory: true) }
    private var cloudDataDir: URL { root.appendingPathComponent("data", isDirectory: true) }
    private var ownSnapshotURL: URL { devicesDir.appendingPathComponent(AppSettings.shared.deviceID + ".json") }

    var isAvailable: Bool { fm.fileExists(atPath: iCloudDriveRoot.path) }
    private var enabled: Bool { AppSettings.shared.iCloudSync && isAvailable }

    func start() {
        settingChanged()
    }

    func settingChanged() {
        timer?.invalidate(); timer = nil
        guard AppSettings.shared.iCloudSync else { status = .off; return }
        guard isAvailable else { status = .unavailable; return }
        try? fm.createDirectory(at: devicesDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: cloudDataDir, withIntermediateDirectories: true)
        seen = [:]
        pull()
        push()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.pull() }
    }

    /// Writes this Mac's snapshot and uploads any payload files the cloud doesn't have yet.
    func push() {
        guard enabled else { return }
        let store = ClipStore.shared
        let snap = store.snapshot
        let files = snap.items.flatMap(\.ownedFiles)
        let localData = store.dataDir
        status = .syncing
        io.async { [self] in
            do {
                for name in files {
                    let dst = cloudDataDir.appendingPathComponent(name)
                    let src = localData.appendingPathComponent(name)
                    if !fm.fileExists(atPath: dst.path), fm.fileExists(atPath: src.path) {
                        try? fm.copyItem(at: src, to: dst)
                    }
                }
                let data = try JSONEncoder().encode(snap)
                try data.write(to: ownSnapshotURL, options: .atomic)
                DispatchQueue.main.async { self.status = .synced(Date()) }
            } catch {
                DispatchQueue.main.async { self.status = .error(error.localizedDescription) }
            }
        }
    }

    /// Reads other Macs' snapshots that changed since the last merge.
    func pull() {
        guard enabled else { return }
        let ownName = ownSnapshotURL.lastPathComponent
        io.async { [self] in
            guard let urls = try? fm.contentsOfDirectory(at: devicesDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
            var snapshots: [(String, Date, LibrarySnapshot)] = []
            for url in urls {
                let name = url.lastPathComponent
                // iCloud may keep a not-yet-downloaded placeholder named ".<name>.icloud".
                if name.hasPrefix("."), name.hasSuffix(".icloud") {
                    try? fm.startDownloadingUbiquitousItem(at: url)
                    continue
                }
                guard name.hasSuffix(".json"), name != ownName else { continue }
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if let last = seen[name], last >= mod { continue }
                guard let data = try? Data(contentsOf: url),
                      let snap = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) else { continue }
                snapshots.append((name, mod, snap))
            }
            guard !snapshots.isEmpty else { return }
            DispatchQueue.main.async {
                var changed = false
                for (name, mod, snap) in snapshots {
                    changed = ClipStore.shared.merge(snap) || changed
                    self.seen[name] = mod
                }
                self.status = .synced(Date())
                if changed { self.push() }  // propagate merged tombstones/records
            }
        }
    }

    /// Copies a payload file from iCloud Drive into the local data directory (on demand).
    func fetchCloudData(_ name: String) -> Data? {
        guard enabled else { return nil }
        let src = cloudDataDir.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: src) else {
            try? fm.startDownloadingUbiquitousItem(at: src)
            return nil
        }
        try? data.write(to: ClipStore.shared.dataURL(name))
        return data
    }

    func deleteCloudData(_ name: String) {
        guard enabled else { return }
        let url = cloudDataDir.appendingPathComponent(name)
        io.async { try? self.fm.removeItem(at: url) }
    }

    var statusText: String {
        switch status {
        case .off: return ""
        case .unavailable: return "iCloud Drive unavailable"
        case .syncing: return "Syncing…"
        case .synced(let d):
            return Date().timeIntervalSince(d) < 60 ? "Synced now" : "Synced " + RelativeDateTimeFormatter().localizedString(for: d, relativeTo: Date())
        case .error(let e): return e
        }
    }
}
