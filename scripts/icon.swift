import AppKit

enum IconGenerationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

func generateIcon() throws {
    guard CommandLine.arguments.count == 2 else {
        throw IconGenerationError.invalid("Usage: swift scripts/icon.swift <resources-directory>")
    }
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let masterURL = root.appendingPathComponent("Vale.png")
    guard FileManager.default.fileExists(atPath: masterURL.path) else {
        throw IconGenerationError.invalid("Missing icon master: \(masterURL.path). Supply a 1024 x 1024 PNG.")
    }
    let data = try Data(contentsOf: masterURL)
    guard data.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
          let master = NSBitmapImageRep(data: data), let cgImage = master.cgImage else {
        throw IconGenerationError.invalid("Invalid or corrupt icon master: \(masterURL.path). Expected a PNG image.")
    }
    guard master.pixelsWide == 1024, master.pixelsHigh == 1024 else {
        throw IconGenerationError.invalid("Icon master must be 1024 x 1024 pixels; found \(master.pixelsWide) x \(master.pixelsHigh).")
    }

    let source = NSImage(cgImage: cgImage, size: NSSize(width: 1024, height: 1024))
    let iconset = root.appendingPathComponent("Vale.iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = size * scale
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                isPlanar: false, colorSpaceName: .calibratedRGB,
                                                bytesPerRow: pixels * 4, bitsPerPixel: 32),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                throw IconGenerationError.invalid("Could not create \(pixels) x \(pixels) icon bitmap.")
            }
            bitmap.size = NSSize(width: pixels, height: pixels)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
                        from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw IconGenerationError.invalid("Could not encode \(pixels) x \(pixels) icon PNG.")
            }
            let suffix = scale == 2 ? "@2x" : ""
            try png.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"), options: .atomic)
        }
    }
    print("Generated Vale.iconset from Vale.png (1024 x 1024).")
}

do {
    try generateIcon()
} catch {
    FileHandle.standardError.write(Data("Icon generation failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
