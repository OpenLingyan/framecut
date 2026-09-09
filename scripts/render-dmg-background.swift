import AppKit

// Draw the installer artwork from code, with no external assets or font files.
guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift render-dmg-background.swift <output-directory>")
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let canvasSize = NSSize(width: 660, height: 440)

for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width) * scale,
        pixelsHigh: Int(canvasSize.height) * scale,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmap.size = canvasSize
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(scale))
    transform.concat()

    NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.98, alpha: 1).setFill()
    NSRect(origin: .zero, size: canvasSize).fill()

    func label(_ text: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (text as NSString).draw(
            in: NSRect(x: 30, y: y, width: 600, height: size * 1.6),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    let ink = NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.20, alpha: 1)
    let muted = NSColor(calibratedRed: 0.39, green: 0.41, blue: 0.48, alpha: 1)
    label("Install FrameCut", y: 352, size: 28, weight: .semibold, color: ink)
    label("Drag FrameCut to Applications", y: 320, size: 16, weight: .regular, color: muted)

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 305, y: 230))
    arrow.line(to: NSPoint(x: 355, y: 230))
    arrow.move(to: NSPoint(x: 343, y: 242))
    arrow.line(to: NSPoint(x: 355, y: 230))
    arrow.line(to: NSPoint(x: 343, y: 218))
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor(calibratedRed: 0.72, green: 0.43, blue: 0.16, alpha: 1).setStroke()
    arrow.stroke()

    // This localized instruction is intentionally bilingual for app users.
    label("将 FrameCut 拖入 Applications 文件夹完成安装", y: 99, size: 15, weight: .medium, color: ink)
    label("Then open FrameCut from Applications and eject this disk.", y: 65, size: 12, weight: .regular, color: muted)
    label("macOS 14+  ·  Apple Silicon & Intel", y: 27, size: 11, weight: .regular, color: muted)

    NSGraphicsContext.restoreGraphicsState()
    let filename = scale == 1 ? "installer.png" : "installer@2x.png"
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: outputDirectory.appendingPathComponent(filename))
}
