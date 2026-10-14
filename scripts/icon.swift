import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("Vale.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let r = CGFloat(pixels)
        let box = NSRect(x: r * 0.09, y: r * 0.09, width: r * 0.82, height: r * 0.82)
        NSColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1).setFill()
        NSBezierPath(roundedRect: box, xRadius: r * 0.20, yRadius: r * 0.20).fill()
        let inset = NSRect(x: r * 0.22, y: r * 0.22, width: r * 0.56, height: r * 0.56)
        let path = NSBezierPath(roundedRect: inset, xRadius: r * 0.13, yRadius: r * 0.13)
        NSGradient(starting: NSColor(red: 0.76, green: 0.82, blue: 1, alpha: 1), ending: NSColor(red: 0.48, green: 0.59, blue: 0.98, alpha: 1))!.draw(in: path, angle: -90)
        let text = "V" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: r * 0.39, weight: .bold), .foregroundColor: NSColor(red: 0.13, green: 0.23, blue: 0.62, alpha: 1)]
        let measure = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (r - measure.width) / 2, y: (r - measure.height) / 2 + r * 0.01), withAttributes: attrs)
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
