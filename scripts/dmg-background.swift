#!/usr/bin/swift
// Draws the disk-image window background (dark, an arrow from the app to the
// Applications shortcut, a caption) at 1x and 2x. Used by release-mac.sh, which
// combines the two PNGs into one HiDPI TIFF with tiffutil.
//
//   swift scripts/dmg-background.swift <out-prefix>   -> <out-prefix>@1x.png, <out-prefix>@2x.png
//
// Geometry matches the Finder layout in release-mac.sh: a 660x420 window with
// 128pt icons centred at x=165 (app) and x=495 (Applications), y=190 from the top.
import AppKit

let prefix = CommandLine.arguments.dropFirst().first ?? "dmg-background"
let width: CGFloat = 660, height: CGFloat = 420
let iconY: CGFloat = height - 190   // AppKit draws from the bottom

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    // Arrow between the two icons.
    let arrow = NSBezierPath()
    arrow.lineWidth = 6
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 262, y: iconY))
    arrow.line(to: NSPoint(x: 398, y: iconY))
    arrow.move(to: NSPoint(x: 372, y: iconY + 24))
    arrow.line(to: NSPoint(x: 398, y: iconY))
    arrow.line(to: NSPoint(x: 372, y: iconY - 24))
    NSColor(calibratedWhite: 0.55, alpha: 1).setStroke()
    arrow.stroke()

    let caption = "Drag PhotoSwipe to Applications" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.7, alpha: 1),
    ]
    let size = caption.size(withAttributes: attrs)
    caption.draw(at: NSPoint(x: (width - size.width) / 2, y: 62), withAttributes: attrs)

    return rep.representation(using: .png, properties: [:])!
}

do {
    try render(scale: 1).write(to: URL(fileURLWithPath: prefix + "@1x.png"))
    try render(scale: 2).write(to: URL(fileURLWithPath: prefix + "@2x.png"))
} catch {
    FileHandle.standardError.write("dmg-background: \(error)\n".data(using: .utf8)!)
    exit(1)
}
