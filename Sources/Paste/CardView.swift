import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let relFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    f.dateTimeStyle = .numeric
    return f
}()

func relativeTime(_ date: Date, now: Date) -> String {
    now.timeIntervalSince(date) < 60 ? "Just now" : relFormatter.localizedString(for: date, relativeTo: now)
}

struct CardView: View {
    @EnvironmentObject var model: PanelModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.colorScheme) var scheme
    let item: ClipItem
    let index: Int
    let now: Date

    var selected: Bool { model.selection.contains(item.id) }

    var body: some View {
        CardFace(item: item, now: now)
        .overlay(alignment: .bottom) {
            if model.quickPasteHeld && index < 9 {
                Text(settingsGlyph + "\(index + 1)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(.ultraThickMaterial))
                    .padding(.bottom, 8)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius + 4, style: .continuous)
                .strokeBorder(ringColor, lineWidth: 4)
                .padding(-4)
                .opacity(selected ? 1 : 0)
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.12), radius: 6, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius))
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            if NSApp.currentEvent?.clickCount == 2 { model.paste([item.id]); return }
            model.select(item.id, extend: flags.contains(.shift), toggle: flags.contains(.command))
        }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { _ in
                    guard !CardDragger.shared.isDragging else { return }
                    // Dragging a selected card carries the whole selection (in shelf order).
                    let ids: [UUID]
                    if selected && model.selection.count > 1 {
                        ids = model.visibleItems.map(\.id).filter { model.selection.contains($0) }
                    } else {
                        model.select(item.id)
                        ids = [item.id]
                    }
                    CardDragger.shared.start(ids: ids)
                }
        )
        .contextMenu { CardMenu(item: item) }
    }

    var settingsGlyph: String {
        switch settings.quickPasteModifier {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        case .shift: "⇧"
        }
    }

    var ringColor: Color {
        model.searchActive || !model.isKey ? Color.white.opacity(0.55) : Metrics.selectionBlue
    }
}

/// The card's visuals (header + body) without selection, gestures or menus — shared by the shelf and drag previews.
struct CardFace: View {
    @Environment(\.colorScheme) var scheme
    let item: ClipItem
    let now: Date

    var bodyColor: Color {
        switch item.kind {
        case .image, .file: scheme == .dark ? Color(white: 30 / 255) : Color(white: 0.96)
        default: scheme == .dark ? Color(white: 20 / 255) : .white
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            CardHeader(item: item, now: now)
            CardBody(item: item)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Metrics.cardWidth, height: Metrics.cardHeight)
        .background(bodyColor)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}

struct CardHeader: View {
    @EnvironmentObject var model: PanelModel
    @EnvironmentObject var store: ClipStore
    let item: ClipItem
    let now: Date
    @State private var draft = ""
    @FocusState private var focused: Bool

    var color: Color { AppIconCache.shared.color(for: item.appBundleID) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            color
            Image(nsImage: AppIconCache.shared.icon(for: item.appBundleID))
                .resizable().interpolation(.high)
                .frame(width: 64, height: 64)
                .offset(x: Metrics.cardWidth - 58, y: -6)
            VStack(alignment: .leading, spacing: 0) {
                if model.renamingItem == item.id {
                    TextField(item.kind.displayName, text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .semibold))
                        .focused($focused)
                        .onSubmit(commit)
                        .onAppear { draft = item.title ?? ""; DispatchQueue.main.async { focused = true } }
                        .onChange(of: focused) { f in if !f { commit() } }
                        .frame(width: Metrics.cardWidth - 84)
                } else {
                    Text(item.displayTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: Metrics.cardWidth - 84, alignment: .leading)
                }
                Text(relativeTime(item.createdAt, now: now))
                    .font(.system(size: 13))
                    .opacity(0.85)
                    .lineLimit(1)
            }
            .foregroundStyle(color.isLight ? Color.black.opacity(0.85) : .white)
            .padding(.leading, 12)
            .frame(height: Metrics.headerHeight)
        }
        .frame(width: Metrics.cardWidth, height: Metrics.headerHeight, alignment: .topLeading)
        .clipped()
    }

    private func commit() {
        guard model.renamingItem == item.id else { return }
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        store.update(item.id) { $0.title = t.isEmpty ? nil : t }
        model.renamingItem = nil
    }
}

struct CardBody: View {
    @ObservedObject var thumbs = ThumbnailCache.shared
    @Environment(\.colorScheme) var scheme
    let item: ClipItem

    var body: some View {
        switch item.kind {
        case .text: textBody
        case .color: colorBody
        case .image: imageBody
        case .link: linkBody
        case .file: fileBody
        }
    }

    private var footerColor: Color { scheme == .dark ? Color(white: 0.6) : Color(white: 0.45) }

    private func footer(_ s: String) -> some View {
        Text(s).font(.system(size: 13)).foregroundStyle(footerColor).lineLimit(1).padding(.bottom, 11)
    }

    private var textBody: some View {
        VStack(spacing: 0) {
            Text(item.text?.isEmpty == false ? String(item.text!.prefix(600)) : " ")
                .font(.system(size: 13))
                .foregroundStyle(scheme == .dark ? Color(white: 0.86) : Color(white: 0.1))
                .lineSpacing(1.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.top, 11)
                .clipped()
            footer(characterCount(item.text ?? ""))
        }
    }

    private var colorBody: some View {
        let c = Color(hex: item.text ?? "") ?? .gray
        return ZStack {
            c
            Text(item.text?.uppercased() ?? "")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(c.isLight ? Color.black.opacity(0.8) : .white)
        }
    }

    private var imageBody: some View {
        ZStack(alignment: .bottom) {
            Checkerboard(dark: scheme == .dark)
            if let img = ImageCache.shared.image(item.imageFile) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let s = item.imageSize {
                Text("\(Int(s.width)) × \(Int(s.height))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).frame(height: 22)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(.bottom, 8)
            }
        }
        .clipped()
    }

    private var linkBody: some View {
        let url = URL(string: item.text ?? "")
        return VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let img = ImageCache.shared.image(item.linkImageFile) {
                    Color(white: scheme == .dark ? 0.12 : 0.93)
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: Metrics.cardWidth, height: 116).clipped()
                } else {
                    Color(white: scheme == .dark ? 0.12 : 0.93)
                    Image(systemName: "link").font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
                }
            }
            .frame(width: Metrics.cardWidth, height: 116)
            .clipped()
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.linkTitle ?? url?.host ?? item.text ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(scheme == .dark ? Color(white: 0.92) : .black)
                    .lineLimit(1)
                Text(displayURL(url) ?? item.text ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(footerColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 11)
        }
    }

    private var fileBody: some View {
        let paths = item.fileURLs ?? []
        let first = paths.first ?? ""
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            Group {
                if let t = thumbs.thumbnail(for: first) {
                    Image(nsImage: t).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first)).resizable().aspectRatio(contentMode: .fit)
                }
            }
            .frame(maxWidth: 150, maxHeight: 96)
            Spacer(minLength: 0)
            Text(paths.count > 1 ? "\(paths.count) files" : (first as NSString).abbreviatingWithTildeInPath)
                .font(.system(size: 13))
                .foregroundStyle(scheme == .dark ? Color(white: 0.75) : Color(white: 0.3))
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 11)
        }
    }

    private func characterCount(_ s: String) -> String {
        let n = s.count
        return n == 1 ? "1 character" : "\(n.formatted()) characters"
    }

    private func displayURL(_ url: URL?) -> String? {
        guard let url, let host = url.host else { return nil }
        let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = url.path == "/" ? "" : url.path
        return h + path
    }
}

struct Checkerboard: View {
    let dark: Bool
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 10
            let a = dark ? Color(white: 0.16) : Color(white: 0.92)
            let b = dark ? Color(white: 0.11) : Color(white: 0.84)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(a))
            for row in 0..<Int(size.height / s) + 1 {
                for col in 0..<Int(size.width / s) + 1 where (row + col) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: CGFloat(col) * s, y: CGFloat(row) * s, width: s, height: s)), with: .color(b))
                }
            }
        }
    }
}

// MARK: - Context menu

struct CardMenu: View {
    @EnvironmentObject var model: PanelModel
    @EnvironmentObject var store: ClipStore
    let item: ClipItem

    /// Act on the whole selection when right-clicking a selected card, otherwise just this card.
    var targets: [UUID] { model.selection.contains(item.id) ? model.selection : [item.id] }

    var body: some View {
        Button("Paste to \(model.targetAppName)") { model.paste(targets) }.keyboardShortcut(.return, modifiers: [])
        Button("Paste as Plain Text") { model.paste(targets, plainText: true) }.keyboardShortcut(.return, modifiers: .shift)
        Button("Copy") { model.copy(targets) }.keyboardShortcut("c")
        Divider()
        if [.text, .link, .color].contains(item.kind) {
            Button("Edit") { model.startEdit(item.id) }.keyboardShortcut("e")
        }
        Button("Rename") { model.startRename(item.id) }.keyboardShortcut("r")
        Button("Duplicate") { if let n = store.duplicate(item.id) { model.select(n) } }.keyboardShortcut("d")
        Button("Delete") { model.delete(targets) }.keyboardShortcut(.delete, modifiers: [])
        Divider()
        Menu("Pin") {
            ForEach(store.sortedPinboards) { board in
                Button {
                    model.pin(targets, to: board.id)
                } label: {
                    Label(board.name, systemImage: item.pinboardID == board.id ? "checkmark" : "circle.fill")
                }
            }
            if !store.pinboards.isEmpty { Divider() }
            Button("New Pinboard") { model.pinToNewPinboard(targets) }
        }
        if case .pinboard = model.list {
            Button("Unpin") { store.remove(Set(targets), from: model.list) }
        }
        Button("Add to Paste Stack") { PasteStack.shared.add(targets) }
        Divider()
        Button("Preview") { model.select(item.id); model.previewItem = item.id }.keyboardShortcut(.space, modifiers: [])
        switch item.kind {
        case .link: Button("Open in Browser") { model.open(item.id) }
        case .file:
            Button("Open") { model.open(item.id) }
            Button("Reveal in Finder") { model.revealInFinder(item.id) }
        case .image: Button("Open in Preview") { model.open(item.id) }
        default: EmptyView()
        }
        Menu("Share") {
            ForEach(NSSharingService.sharingServices(forItems: model.shareItems(item)), id: \.title) { service in
                Button { model.share(item.id, via: service) } label: {
                    Label { Text(service.title) } icon: { Image(nsImage: service.image) }
                }
            }
        }
    }
}

// MARK: - Editor

struct EditorOverlay: View {
    @EnvironmentObject var model: PanelModel
    @EnvironmentObject var store: ClipStore
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).onTapGesture { model.finishEdit(save: text) }
            VStack(spacing: 0) {
                HStack {
                    Text(model.editingIsNew ? "New Text Item" : "Edit").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("\(text.count) characters").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).frame(height: 36)
                Divider()
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .padding(8)
                Divider()
                HStack {
                    Spacer()
                    Button("Cancel") { model.finishEdit(save: nil) }
                    Button("Save") { model.finishEdit(save: text) }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                }
                .padding(10)
            }
            .frame(width: 620, height: 236)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
            .shadow(radius: 20)
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous))
        .onAppear {
            text = model.editingItem.flatMap { store.item($0)?.text } ?? ""
            DispatchQueue.main.async { focused = true }
        }
    }
}

// MARK: - Preview (Space)

struct PreviewContainer: View {
    @EnvironmentObject var model: PanelModel
    @EnvironmentObject var store: ClipStore
    @Environment(\.colorScheme) var scheme

    var body: some View {
        if let id = model.previewItem, let item = store.item(id) {
            VStack(spacing: 0) {
                CardHeader(item: item, now: Date())
                    .frame(width: 640)
                    .environmentObject(model)
                content(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Text(item.appName.map { "Copied from \($0)" } ?? "").foregroundStyle(.secondary)
                    Spacer()
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 14).frame(height: 32)
            }
            .background(scheme == .dark ? Color(white: 0.09) : .white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
        }
    }

    @ViewBuilder
    private func content(_ item: ClipItem) -> some View {
        switch item.kind {
        case .text, .color:
            if item.kind == .color, let c = Color(hex: item.text ?? "") {
                c.overlay(Text(item.text ?? "").font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(c.isLight ? .black : .white))
            } else {
                ScrollView {
                    Text(item.text ?? "").font(.system(size: 14)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading).padding(16)
                }
            }
        case .image:
            ZStack {
                Checkerboard(dark: scheme == .dark)
                if let img = ImageCache.shared.image(item.imageFile) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).padding(8)
                }
            }
        case .link:
            VStack(alignment: .leading, spacing: 8) {
                if let img = ImageCache.shared.image(item.linkImageFile) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if let t = item.linkTitle { Text(t).font(.system(size: 16, weight: .semibold)) }
                Text(item.text ?? "").font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .padding(16)
        case .file:
            VStack(spacing: 12) {
                if let first = item.fileURLs?.first {
                    Image(nsImage: ThumbnailCache.shared.thumbnail(for: first) ?? NSWorkspace.shared.icon(forFile: first))
                        .resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 260)
                }
                ForEach(item.fileURLs ?? [], id: \.self) { p in
                    Text((p as NSString).abbreviatingWithTildeInPath).font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(16)
        }
    }
}
