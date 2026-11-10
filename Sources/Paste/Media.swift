import AppKit
import LinkPresentation
import QuickLookThumbnailing
import SwiftUI

/// App icons and their dominant colour (used for the card header).
final class AppIconCache {
    static let shared = AppIconCache()
    private var icons: [String: NSImage] = [:]
    private var colors: [String: Color] = [:]

    func icon(for bundleID: String?) -> NSImage {
        let key = bundleID ?? "_unknown"
        if let i = icons[key] { return i }
        let img: NSImage
        if let bid = bundleID, bid == Bundle.main.bundleIdentifier {
            img = NSApp.applicationIconImage
        } else if let bid = bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            img = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            img = NSWorkspace.shared.icon(for: .application)
        }
        icons[key] = img
        return img
    }

    func color(for bundleID: String?) -> Color {
        let key = bundleID ?? "_unknown"
        if let c = colors[key] { return c }
        let c = Self.dominantColor(of: icon(for: bundleID)) ?? Color(white: 0.35)
        colors[key] = c
        return c
    }

    /// Picks the most common saturated colour in the icon; falls back to the average.
    static func dominantColor(of image: NSImage) -> Color? {
        let size = 32
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let ptr = ctx.data?.bindMemory(to: UInt8.self, capacity: size * size * 4) else { return nil }

        var buckets: [Int: (count: Double, r: Double, g: Double, b: Double)] = [:]
        var avg = (r: 0.0, g: 0.0, b: 0.0, n: 0.0)
        for i in 0..<(size * size) {
            let a = Double(ptr[i * 4 + 3]) / 255
            guard a > 0.6 else { continue }
            let r = Double(ptr[i * 4]) / 255 / a, g = Double(ptr[i * 4 + 1]) / 255 / a, b = Double(ptr[i * 4 + 2]) / 255 / a
            avg.r += r; avg.g += g; avg.b += b; avg.n += 1
            let mx = max(r, g, b), mn = min(r, g, b)
            let sat = mx == 0 ? 0 : (mx - mn) / mx
            guard sat > 0.25, mx > 0.2 else { continue }
            // Hue bucket
            var h: Double
            if mx == r { h = (g - b) / (mx - mn) } else if mx == g { h = 2 + (b - r) / (mx - mn) } else { h = 4 + (r - g) / (mx - mn) }
            h = (h * 60).truncatingRemainder(dividingBy: 360); if h < 0 { h += 360 }
            let key = Int(h / 20)
            var e = buckets[key] ?? (0, 0, 0, 0)
            let w = sat * mx
            e.count += w; e.r += r * w; e.g += g * w; e.b += b * w
            buckets[key] = e
        }
        if let best = buckets.values.max(by: { $0.count < $1.count }), best.count > 8 {
            return Color(red: best.r / best.count, green: best.g / best.count, blue: best.b / best.count)
        }
        guard avg.n > 0 else { return nil }
        return Color(red: avg.r / avg.n, green: avg.g / avg.n, blue: avg.b / avg.n)
    }
}

/// QuickLook thumbnails for file cards.
final class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()
    @Published private(set) var thumbs: [String: NSImage] = [:]
    private var pending = Set<String>()

    func thumbnail(for path: String) -> NSImage? {
        if let t = thumbs[path] { return t }
        guard !pending.contains(path) else { return nil }
        pending.insert(path)
        let req = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path), size: CGSize(width: 400, height: 300),
                                               scale: 2, representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            let img = rep?.nsImage ?? NSWorkspace.shared.icon(forFile: path)
            DispatchQueue.main.async { self.thumbs[path] = img }
        }
        return nil
    }
}

/// Loads images from the data dir with a small in-memory cache.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(_ name: String?) -> NSImage? {
        guard let name else { return nil }
        if let i = cache.object(forKey: name as NSString) { return i }
        guard let data = ClipStore.shared.readData(name), let img = NSImage(data: data) else { return nil }
        cache.setObject(img, forKey: name as NSString)
        return img
    }
}

/// Fetches title + preview image for link cards.
final class LinkPreviewer {
    static let shared = LinkPreviewer()
    private var inFlight = Set<UUID>()

    func fetchIfNeeded(_ id: UUID) {
        guard AppSettings.shared.linkPreviews, !inFlight.contains(id),
              let item = ClipStore.shared.item(id), item.kind == .link, !item.linkPreviewFetched,
              let s = item.text, let url = URL(string: s) else { return }
        inFlight.insert(id)
        let provider = LPMetadataProvider()
        provider.timeout = 12
        provider.startFetchingMetadata(for: url) { meta, _ in
            let title = meta?.title
            let imageProvider = meta?.imageProvider ?? meta?.iconProvider
            let finish: (Data?) -> Void = { png in
                DispatchQueue.main.async {
                    self.inFlight.remove(id)
                    ClipStore.shared.update(id) { item in
                        item.linkPreviewFetched = true
                        item.linkTitle = title
                        if let png { item.linkImageFile = ClipStore.shared.writeData(png, ext: "png") }
                    }
                }
            }
            guard let imageProvider else { finish(nil); return }
            imageProvider.loadObject(ofClass: NSImage.self) { obj, _ in
                guard let img = obj as? NSImage else { finish(nil); return }
                finish(img.downscaledPNG(maxSide: 800))
            }
        }
    }
}

extension NSImage {
    func downscaledPNG(maxSide: CGFloat) -> Data? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxSide / max(w, h))
        let nw = Int(w * scale), nh = Int(h * scale)
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        guard let out = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        let r = Double((v >> (hasAlpha ? 24 : 16)) & 0xff) / 255
        let g = Double((v >> (hasAlpha ? 16 : 8)) & 0xff) / 255
        let b = Double((v >> (hasAlpha ? 8 : 0)) & 0xff) / 255
        let a = hasAlpha ? Double(v & 0xff) / 255 : 1
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Relative luminance, used to pick legible text on colour swatches.
    var isLight: Bool {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return false }
        return (0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent) > 0.6
    }
}
