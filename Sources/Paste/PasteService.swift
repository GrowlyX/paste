import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Writes items back to the pasteboard and (optionally) types ⌘V into the frontmost app.
enum PasteService {
    static func write(_ items: [ClipItem], plainText: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let store = ClipStore.shared

        if items.count == 1, let item = items.first {
            switch item.kind {
            case .image:
                if let data = store.readData(item.imageFile) {
                    pb.setData(data, forType: .png)
                    if let img = NSImage(data: data), let tiff = img.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
                }
            case .file:
                pb.writeObjects((item.fileURLs ?? []).map { URL(fileURLWithPath: $0) as NSURL })
            case .link:
                let s = item.text ?? ""
                pb.setString(s, forType: .string)
                if !plainText, let url = URL(string: s) { pb.setString(url.absoluteString, forType: .URL) }
            case .text, .color:
                pb.setString(item.text ?? "", forType: .string)
                if !plainText {
                    if let rtf = store.readData(item.rtfFile) { pb.setData(rtf, forType: .rtf) }
                    if let html = store.readData(item.htmlFile) { pb.setData(html, forType: .html) }
                }
            }
        } else {
            // Several items: join textual representations, one per line.
            let joined = items.map(textRepresentation).joined(separator: "\n")
            pb.setString(joined, forType: .string)
        }
        ClipboardMonitor.shared.ignoreChangeCount = pb.changeCount
    }

    static func textRepresentation(_ item: ClipItem) -> String {
        switch item.kind {
        case .file: return (item.fileURLs ?? []).joined(separator: "\n")
        case .image: return item.title ?? "Image"
        default: return item.text ?? ""
        }
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// Simulates ⌘V in whatever app is frontmost.
    static func sendPasteKeystroke() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
