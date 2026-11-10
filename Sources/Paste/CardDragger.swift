import AppKit
import SwiftUI

/// Drags one or more cards out of the shelf as a single AppKit dragging session.
///
/// Pasteboard layout (so every kind of destination gets something sensible):
///   • all textual cards (text, links, colors) → ONE string item, joined with newlines,
///     so dropping into any text field pastes the whole selection at once
///   • each image → its own item (PNG data + file URL), so Finder makes real files
///   • each file  → its own file-URL item
/// The drag image is a fanned "deck" of the selected cards with a count badge.
final class CardDragger: NSObject, NSDraggingSource {
    static let shared = CardDragger()
    private(set) var isDragging = false

    @MainActor
    func start(ids: [UUID]) {
        let store = ClipStore.shared
        let items = ids.compactMap { store.item($0) }
        guard !items.isEmpty, let view = PanelController.shared.shelfView,
              let event = NSApp.currentEvent, [.leftMouseDragged, .leftMouseDown].contains(event.type) else { return }

        isDragging = true
        PanelModel.shared.draggingIDs = items.map(\.id)

        let writers = pasteboardItems(for: items)
        guard !writers.isEmpty else { isDragging = false; return }

        let deck = DeckRenderer.image(for: items)
        let point = view.convert(event.locationInWindow, from: nil)
        let frame = NSRect(x: point.x - deck.size.width / 2, y: point.y - deck.size.height / 2,
                           width: deck.size.width, height: deck.size.height)

        // Only the first dragging item draws (the whole deck); the rest ride along invisibly.
        let dragItems: [NSDraggingItem] = writers.enumerated().map { i, writer in
            let d = NSDraggingItem(pasteboardWriter: writer)
            d.setDraggingFrame(frame, contents: i == 0 ? deck : nil)
            return d
        }
        debugLog("drag start: \(items.count) cards -> \(writers.count) pasteboard items, event=\(event.type.rawValue)")
        let session = view.beginDraggingSession(with: dragItems, event: event, source: self)
        session.draggingFormation = .none
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    // MARK: Pasteboard

    private func pasteboardItems(for items: [ClipItem]) -> [NSPasteboardItem] {
        let store = ClipStore.shared
        var out: [NSPasteboardItem] = []

        let textual = items.filter { [.text, .link, .color].contains($0.kind) }
        if textual.count == 1, let only = textual.first {
            let pi = NSPasteboardItem()
            pi.setString(only.text ?? "", forType: .string)
            if only.kind == .link, let url = URL(string: only.text ?? "") { pi.setString(url.absoluteString, forType: .URL) }
            if items.count == 1, let rtf = store.readData(only.rtfFile) { pi.setData(rtf, forType: .rtf) }
            out.append(pi)
        } else if textual.count > 1 {
            let pi = NSPasteboardItem()
            pi.setString(textual.map { $0.text ?? "" }.joined(separator: "\n"), forType: .string)
            out.append(pi)
        }

        for item in items {
            switch item.kind {
            case .image:
                guard let name = item.imageFile, let data = store.readData(name) else { continue }
                let pi = NSPasteboardItem()
                pi.setData(data, forType: .png)
                pi.setString(store.dataURL(name).absoluteString, forType: .fileURL)
                out.append(pi)
            case .file:
                for path in item.fileURLs ?? [] {
                    let pi = NSPasteboardItem()
                    pi.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
                    out.append(pi)
                }
            default:
                break
            }
        }
        return out
    }

    // MARK: NSDraggingSource

    @objc func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Include .generic: holding ⌘ (common right after ⌘-clicking cards) narrows a drag to generic only.
        [.copy, .generic]
    }

    @objc func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
        debugLog("drag ended at \(screenPoint) operation=\(operation.rawValue)")
        if operation != [] { SoundFX.paste() }
        // Drop targets inside the shelf read draggingIDs during the drop; clear afterwards.
        DispatchQueue.main.async { PanelModel.shared.draggingIDs = [] }
    }
}

/// Renders the drag image: up to four cards fanned like a deck, plus a count badge.
enum DeckRenderer {
    static let scale: CGFloat = 1.3

    @MainActor
    static func image(for items: [ClipItem]) -> NSImage {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let view = DeckPreview(items: Array(items.prefix(4)), total: items.count)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environmentObject(PanelModel.shared)
            .environmentObject(ClipStore.shared)
            .environmentObject(AppSettings.shared)
        let renderer = ImageRenderer(content: view)
        renderer.scale = (NSScreen.main?.backingScaleFactor ?? 2)
        guard let img = renderer.nsImage else { return NSImage(size: NSSize(width: 1, height: 1)) }
        img.size = NSSize(width: img.size.width * scale, height: img.size.height * scale)
        return img
    }
}

struct DeckPreview: View {
    let items: [ClipItem]  // first = top of the deck
    let total: Int

    /// Rotation/offset for the card `depth` positions below the top one.
    private func tilt(_ depth: Int) -> (angle: Double, x: CGFloat, y: CGFloat) {
        switch depth {
        case 0: (0, 0, 0)
        case 1: (-5, -10, 6)
        case 2: (6, 12, 10)
        default: (-9, -16, 14)
        }
    }

    var body: some View {
        ZStack {
            ForEach(Array(items.enumerated()).reversed(), id: \.element.id) { depth, item in
                let t = tilt(depth)
                CardFace(item: item, now: Date())
                    .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                            .fill(Color.black.opacity(0.35)).blur(radius: 9).offset(y: 5)
                    )
                    .rotationEffect(.degrees(t.angle))
                    .offset(x: t.x, y: t.y)
            }
        }
        .overlay(alignment: .topTrailing) {
            if total > 1 {
                Text("\(total)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 42, minHeight: 42)
                    .background(Capsule().fill(Metrics.selectionBlue))
                    .overlay(Capsule().strokeBorder(Color.white, lineWidth: 3))
                    .offset(x: 14, y: -14)
            }
        }
        .padding(44)
    }
}
