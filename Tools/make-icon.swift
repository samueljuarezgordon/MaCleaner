import AppKit

let symbolName = "bubbles.and.sparkles.fill"
let out = CommandLine.arguments[1]

func render(size: Int, macStyle: Bool) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS: cuerpo de 824/1024 con margen y sombra. iOS: lienzo completo (el sistema redondea).
    let inset = macStyle ? s * 100 / 1024 : 0
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = macStyle ? body.width * 0.225 : 0
    let path = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    if macStyle {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addPath(path); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let colors = [
        NSColor(red: 0.16, green: 0.20, blue: 0.62, alpha: 1).cgColor,
        NSColor(red: 0.45, green: 0.22, blue: 0.85, alpha: 1).cgColor,
        NSColor(red: 0.93, green: 0.36, blue: 0.62, alpha: 1).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
    // Brillo superior suave.
    let gloss = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [NSColor.white.withAlphaComponent(0.22).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(gloss, start: CGPoint(x: body.midX, y: body.maxY), end: CGPoint(x: body.midX, y: body.midY), options: [])
    ctx.restoreGState()

    // Símbolo blanco centrado.
    let config = NSImage.SymbolConfiguration(pointSize: body.width * 0.5, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    let scale = min(body.width * 0.62 / symbol.size.width, body.height * 0.62 / symbol.size.height)
    let w = symbol.size.width * scale, h = symbol.size.height * scale
    let rect = CGRect(x: body.midX - w / 2, y: body.midY - h / 2, width: w, height: h)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.02, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    symbol.draw(in: rect)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let name = "mac-\(points)@\(scale)x.png"
        try! render(size: points * scale, macStyle: true).write(to: URL(fileURLWithPath: out + "/" + name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
try! render(size: 1024, macStyle: false).write(to: URL(fileURLWithPath: out + "/ios-1024.png"))
images.append(["filename": "ios-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"])

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let data = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! data.write(to: URL(fileURLWithPath: out + "/Contents.json"))
print("ok")
