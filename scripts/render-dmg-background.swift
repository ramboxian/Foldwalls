#!/usr/bin/env swift

import AppKit

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: render-dmg-background.swift <base-image> <output-png>\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let baseImage = NSImage(contentsOf: inputURL) else {
    fputs("Unable to load base image: \(inputURL.path)\n", stderr)
    exit(1)
}

// Finder displays this background in a 760 x 500 point content area. Render
// two physical pixels per point so text and vector details stay sharp on
// Retina displays while preserving the exact layout size Finder expects.
let canvasSize = NSSize(width: 760, height: 500)
let pixelScale: CGFloat = 2
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width * pixelScale),
    pixelsHigh: Int(canvasSize.height * pixelScale),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Unable to create bitmap context.\n", stderr)
    exit(1)
}

bitmap.size = canvasSize
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Unable to create graphics context.\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

let canvas = NSRect(origin: .zero, size: canvasSize)
NSColor.black.setFill()
canvas.fill()

let sourceSize = baseImage.size
let scale = max(canvasSize.width / sourceSize.width, canvasSize.height / sourceSize.height)
let drawnSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
let drawnRect = NSRect(
    x: (canvasSize.width - drawnSize.width) / 2,
    y: (canvasSize.height - drawnSize.height) / 2,
    width: drawnSize.width,
    height: drawnSize.height
)
baseImage.draw(in: drawnRect, from: .zero, operation: .sourceOver, fraction: 1)

// Darken the middle just enough to keep Finder labels and instructions crisp.
NSGradient(colors: [
    NSColor.black.withAlphaComponent(0.04),
    NSColor.black.withAlphaComponent(0.26),
    NSColor.black.withAlphaComponent(0.08),
])?.draw(in: canvas, angle: -90)

func drawCenteredText(_ text: String, y: CGFloat, font: NSFont, color: NSColor, tracking: CGFloat = 0) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
        .kern: tracking,
    ]
    NSString(string: text).draw(
        in: NSRect(x: 40, y: y, width: canvasSize.width - 80, height: font.pointSize * 1.5),
        withAttributes: attributes
    )
}

drawCenteredText(
    "FOLDWALLS",
    y: 430,
    font: .systemFont(ofSize: 25, weight: .bold),
    color: NSColor.white.withAlphaComponent(0.94),
    tracking: 3.2
)
drawCenteredText(
    "DYNAMIC WALLPAPERS FOR MAC",
    y: 402,
    font: .systemFont(ofSize: 9.5, weight: .semibold),
    color: NSColor.white.withAlphaComponent(0.46),
    tracking: 2.4
)

// Quiet glass pedestals mark the two Finder icon zones without competing with
// the real app and Applications icons that Finder places above the image.
for centerX in [205.0, 555.0] {
    let zone = NSBezierPath(roundedRect: NSRect(x: centerX - 78, y: 174, width: 156, height: 156), xRadius: 42, yRadius: 42)
    NSColor.white.withAlphaComponent(0.027).setFill()
    zone.fill()
    NSColor.white.withAlphaComponent(0.07).setStroke()
    zone.lineWidth = 0.8
    zone.stroke()
}

// Foldwalls' color fold becomes the drag arrow between the two icons.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 337, y: 246))
arrow.line(to: NSPoint(x: 391, y: 246))
arrow.line(to: NSPoint(x: 391, y: 231))
arrow.line(to: NSPoint(x: 427, y: 260))
arrow.line(to: NSPoint(x: 391, y: 289))
arrow.line(to: NSPoint(x: 391, y: 274))
arrow.line(to: NSPoint(x: 337, y: 274))
arrow.close()

for width in stride(from: 18.0, through: 4.0, by: -3.5) {
    let glow = NSBezierPath()
    glow.append(arrow)
    NSColor(calibratedRed: 0.49, green: 0.22, blue: 1.0, alpha: 0.018).setStroke()
    glow.lineWidth = width
    glow.stroke()
}

NSGradient(colorsAndLocations:
    (NSColor(calibratedRed: 1.0, green: 0.46, blue: 0.12, alpha: 0.98), 0.0),
    (NSColor(calibratedRed: 0.98, green: 0.12, blue: 0.54, alpha: 0.98), 0.48),
    (NSColor(calibratedRed: 0.25, green: 0.30, blue: 1.0, alpha: 0.98), 1.0)
)?.draw(in: arrow, angle: 0)

NSColor.white.withAlphaComponent(0.34).setStroke()
arrow.lineWidth = 0.75
arrow.stroke()

drawCenteredText(
    "将 Foldwalls 拖入 Applications 文件夹",
    y: 71,
    font: .systemFont(ofSize: 17, weight: .semibold),
    color: NSColor.white.withAlphaComponent(0.90)
)
drawCenteredText(
    "安装提示失败：请打开「系统设置 > 隐私与安全性」，选择「仍要打开」",
    y: 42,
    font: .systemFont(ofSize: 11.5, weight: .medium),
    color: NSColor.white.withAlphaComponent(0.48)
)

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode PNG.\n", stderr)
    exit(1)
}

do {
    try png.write(to: outputURL, options: .atomic)
} catch {
    fputs("Unable to write output: \(error.localizedDescription)\n", stderr)
    exit(1)
}
