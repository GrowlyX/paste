// Renders the Paste app icon: solid deep-blue squircle with white "paste" in Macintosh Skeletal Filled.
import AppKit
import CoreText

let args = CommandLine.arguments
let fontURL = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
let descs = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as! [CTFontDescriptor]
let desc = descs[0]

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let k = s / 1024
    let body = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let path = CGPath(roundedRect: body, cornerWidth: 186 * k, cornerHeight: 186 * k, transform: nil)
    // drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 24 * k, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(path); ctx.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    // solid deep blue fill
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.setFillColor(CGColor(red: 0.10, green: 0.36, blue: 0.95, alpha: 1)); ctx.fill(body)
    ctx.restoreGState()
    // text
    var fontSize: CGFloat = 400 * k
    func line(_ fs: CGFloat) -> CTLine {
        let font = CTFontCreateWithFontDescriptor(desc, fs, nil)
        let attr = NSAttributedString(string: "paste", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)])
        return CTLineCreateWithAttributedString(attr)
    }
    var l = line(fontSize)
    var b = CTLineGetImageBounds(l, ctx)
    fontSize *= (640 * k) / b.width
    l = line(fontSize); b = CTLineGetImageBounds(l, ctx)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * k), blur: 14 * k, color: CGColor(red: 0, green: 0.15, blue: 0.45, alpha: 0.35))
    ctx.textPosition = CGPoint(x: body.midX - b.width / 2 - b.minX, y: body.midY - b.height / 2 - b.minY)
    CTLineDraw(l, ctx)
    ctx.restoreGState()
    let img = ctx.makeImage()!
    return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
}

let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(size: 1024).write(to: outDir.appendingPathComponent("AppIcon-1024.png"))
let f = CTFontCreateWithFontDescriptor(desc, 20, nil)
print("font:", CTFontCopyFullName(f))
