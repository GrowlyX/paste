import AppKit

/// Shared pinboards: a pinboard that several people read and write through a shared folder.
///
/// Folder layout (`<Name>.pastepinboard/`), placed anywhere collaborators can all reach —
/// typically an iCloud Drive folder shared with "Collaborate", or Dropbox / Google Drive:
///   pinboard.json               – identity of the pinboard (id, initial name, color)
///   participants/<device>.json  – one file per Mac: its copy of the items + tombstones
///   data/<uuid>.<ext>           – payload files (images, rich text, link previews)
///
/// Every Mac only writes its own participant file, so no two people ever write the same file.
/// Each Mac merges every other participant file with per-item last-writer-wins + tombstones.
final class SharedPinboards: ObservableObject {
    static let shared = SharedPinboards()

    struct Identity: Codable {
        var id: UUID
        var name: String
        var color: PinboardColor
        var createdBy: String
        var createdAt: Date
    }

    struct Participant: Codable {
        var participant: String
        var pinboard: Pinboard
        var items: [ClipItem]
        var tombstones: [UUID: Date]
        var savedAt: Date
    }

    @Published private(set) var participants: [UUID: [String]] = [:]  // board -> names of other people
    @Published private(set) var lastSync: [UUID: Date] = [:]

    static let folderExtension = "pastepinboard"
    private let fm = FileManager.default
    private let io = DispatchQueue(label: "paste.shared", qos: .utility)
    private var seen: [String: Date] = [:]  // participant file path -> merged modification date
    private var timer: Timer?

    private var deviceID: String { AppSettings.shared.deviceID }
    private var personName: String { NSFullUserName().isEmpty ? (Host.current().localizedName ?? "Someone") : NSFullUserName() }

    var sharedBoards: [Pinboard] { ClipStore.shared.pinboards.filter(\.isShared) }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.pullAll() }
        pullAll()
    }

    // MARK: Share / join / leave

    /// Asks where to put the shared folder, creates it, and publishes the pinboard into it.
    func share(_ boardID: UUID) {
        guard let board = ClipStore.shared.pinboard(boardID) else { return }
        let picked: URL? = PanelController.shared.runModal {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Share Here"
            panel.message = "Choose a folder the people you're sharing with can access — for example a shared iCloud Drive folder or Dropbox."
            let icloud = SyncEngine.shared.iCloudDriveRoot
            panel.directoryURL = fm.fileExists(atPath: icloud.path) ? icloud : fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            return panel.runModal() == .OK ? panel.url : nil
        }
        guard let parent = picked else { return }

        let safeName = board.name.replacingOccurrences(of: "/", with: "-")
        var folder = parent.appendingPathComponent("\(safeName).\(Self.folderExtension)", isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: folder.path) {
            folder = parent.appendingPathComponent("\(safeName) \(n).\(Self.folderExtension)", isDirectory: true); n += 1
        }
        do {
            try fm.createDirectory(at: folder.appendingPathComponent("participants"), withIntermediateDirectories: true)
            try fm.createDirectory(at: folder.appendingPathComponent("data"), withIntermediateDirectories: true)
            let identity = Identity(id: board.id, name: board.name, color: board.color, createdBy: personName, createdAt: Date())
            try JSONEncoder.pretty.encode(identity).write(to: folder.appendingPathComponent("pinboard.json"))
        } catch {
            alert("Couldn't share “\(board.name)”", error.localizedDescription)
            return
        }
        ClipStore.shared.updatePinboard(board.id) { $0.sharedFolderPath = folder.path }
        push(boardID)

        NSWorkspace.shared.activateFileViewerSelecting([folder])
        alert("“\(board.name)” is now shared",
              "Give people access to the folder “\(folder.lastPathComponent)” (in Finder: Share › Collaborate for iCloud Drive, or share it from Dropbox). They join it in Paste with ⋯ › Join Shared Pinboard…")
    }

    /// Asks for a `.pastepinboard` folder and adds that pinboard locally.
    func join() {
        let picked: URL? = PanelController.shared.runModal {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.treatsFilePackagesAsDirectories = false
            panel.prompt = "Join"
            panel.message = "Choose a shared pinboard folder (ends in .\(Self.folderExtension))."
            panel.directoryURL = SyncEngine.shared.iCloudDriveRoot
            return panel.runModal() == .OK ? panel.url : nil
        }
        guard let folder = picked else { return }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("pinboard.json")),
              let identity = try? JSONDecoder.iso8601.decode(Identity.self, from: data) else {
            alert("That isn't a shared pinboard", "Pick a folder whose name ends in .\(Self.folderExtension).")
            return
        }
        let store = ClipStore.shared
        if store.pinboard(identity.id) != nil {
            store.updatePinboard(identity.id) { $0.sharedFolderPath = folder.path }
        } else {
            var board = Pinboard(id: identity.id, name: identity.name, color: identity.color)
            board.modifiedAt = .distantPast  // let collaborators' latest name/color win
            board.sharedFolderPath = folder.path
            store.insertPinboard(board)
        }
        try? fm.createDirectory(at: folder.appendingPathComponent("participants"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: folder.appendingPathComponent("data"), withIntermediateDirectories: true)
        PanelModel.shared.list = .pinboard(identity.id)
        pull(identity.id)
        push(identity.id)
    }

    /// Stops syncing this pinboard (keeps the local copy). Removes our participant file so others stop seeing us.
    func leave(_ boardID: UUID) {
        guard let board = ClipStore.shared.pinboard(boardID), let path = board.sharedFolderPath else { return }
        try? fm.removeItem(at: participantURL(folder: URL(fileURLWithPath: path)))
        ClipStore.shared.updatePinboard(boardID) { $0.sharedFolderPath = nil }
        participants[boardID] = nil
    }

    func revealFolder(_ boardID: UUID) {
        guard let path = ClipStore.shared.pinboard(boardID)?.sharedFolderPath else { return }
        PanelController.shared.hide()
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: Sync

    private func participantURL(folder: URL) -> URL {
        folder.appendingPathComponent("participants").appendingPathComponent(deviceID + ".json")
    }

    func pushAll() { sharedBoards.forEach { push($0.id) } }
    func pullAll() { sharedBoards.forEach { pull($0.id) } }

    /// Writes this Mac's copy of the pinboard. Items that we published before but no longer have become tombstones.
    func push(_ boardID: UUID) {
        let store = ClipStore.shared
        guard let board = store.pinboard(boardID), let path = board.sharedFolderPath else { return }
        let folder = URL(fileURLWithPath: path)
        var meta = board
        meta.sharedFolderPath = nil  // local path, meaningless to others
        let items: [ClipItem] = store.items.filter { $0.pinboardID == boardID }.map { item in
            var i = item
            i.inHistory = false
            i.title = item.title
            return i
        }
        let localData = store.dataDir
        let me = personName
        let ownURL = participantURL(folder: folder)
        io.async { [self] in
            var tombstones: [UUID: Date] = [:]
            if let data = try? Data(contentsOf: ownURL), let previous = try? JSONDecoder().decode(Participant.self, from: data) {
                tombstones = previous.tombstones
                let now = Set(items.map(\.id))
                for old in previous.items where !now.contains(old.id) && tombstones[old.id] == nil { tombstones[old.id] = Date() }
            }
            let cutoff = Date().addingTimeInterval(-90 * 86_400)
            tombstones = tombstones.filter { $0.value > cutoff && !items.map(\.id).contains($0.key) }

            let dataDir = folder.appendingPathComponent("data")
            try? fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
            for name in items.flatMap(\.ownedFiles) {
                let dst = dataDir.appendingPathComponent(name)
                let src = localData.appendingPathComponent(name)
                if !fm.fileExists(atPath: dst.path), fm.fileExists(atPath: src.path) { try? fm.copyItem(at: src, to: dst) }
            }
            let record = Participant(participant: me, pinboard: meta, items: items, tombstones: tombstones, savedAt: Date())
            try? fm.createDirectory(at: ownURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(record) { try? data.write(to: ownURL, options: .atomic) }
            DispatchQueue.main.async { self.lastSync[boardID] = Date() }
        }
    }

    /// Reads collaborators' files that changed since we last merged them.
    func pull(_ boardID: UUID) {
        guard let path = ClipStore.shared.pinboard(boardID)?.sharedFolderPath else { return }
        let folder = URL(fileURLWithPath: path)
        let ownName = deviceID + ".json"
        io.async { [self] in
            let dir = folder.appendingPathComponent("participants")
            guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
            var names: [String] = []
            var fresh: [(String, Date, Participant)] = []
            for url in urls {
                let name = url.lastPathComponent
                if name.hasPrefix("."), name.hasSuffix(".icloud") { try? fm.startDownloadingUbiquitousItem(at: url); continue }
                guard name.hasSuffix(".json"), name != ownName,
                      let data = try? Data(contentsOf: url), let p = try? JSONDecoder().decode(Participant.self, from: data) else { continue }
                names.append(p.participant)
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if let last = seen[url.path], last >= mod { continue }
                fresh.append((url.path, mod, p))
            }
            DispatchQueue.main.async {
                self.participants[boardID] = Array(Set(names)).sorted()
                var changed = false
                for (key, mod, p) in fresh {
                    changed = ClipStore.shared.mergeShared(boardID: boardID, meta: p.pinboard, items: p.items, tombstones: p.tombstones) || changed
                    self.seen[key] = mod
                }
                self.lastSync[boardID] = Date()
                if changed {
                    self.push(boardID)
                    for item in ClipStore.shared.items where item.pinboardID == boardID && item.kind == .link && !item.linkPreviewFetched {
                        LinkPreviewer.shared.fetchIfNeeded(item.id)
                    }
                }
            }
        }
    }

    /// Looks for a payload file in every shared pinboard folder and caches it locally.
    func fetchData(_ name: String) -> Data? {
        for board in sharedBoards {
            guard let path = board.sharedFolderPath else { continue }
            let url = URL(fileURLWithPath: path).appendingPathComponent("data").appendingPathComponent(name)
            if let data = try? Data(contentsOf: url) {
                try? data.write(to: ClipStore.shared.dataURL(name))
                return data
            }
            try? fm.startDownloadingUbiquitousItem(at: url)
        }
        return nil
    }

    private func alert(_ title: String, _ text: String) {
        _ = PanelController.shared.runModal {
            let a = NSAlert()
            a.messageText = title
            a.informativeText = text
            a.runModal()
        }
    }
}

extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
