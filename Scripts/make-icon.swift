#!/usr/bin/env swift
// Renders Resources/AppIcon.icns.
//
// The app icon echoes the menu bar item: the raised hand inside a rounded
// frame. Here the frame is the icon's own squircle, so both read as one mark.
//
// Usage: swift Scripts/make-icon.swift [output.icns]

import AppKit

let symbolName = "hand.raised.fill"

/// Apple's macOS icon grid: the rounded square covers 824 of a 1024 canvas,
/// with a corner radius of 185, leaving the margin the system expects.
let plateRatio: CGFloat = 824.0 / 1024.0
let radiusRatio: CGFloat = 185.0 / 1024.0
let glyphRatio: CGFloat = 430.0 / 1024.0

let topColor = NSColor(srgbRed: 0.35, green: 0.60, blue: 1.00, alpha: 1)
let bottomColor = NSColor(srgbRed: 0.09, green: 0.29, blue: 0.83, alpha: 1)

func glyph(height: CGFloat) -> NSImage {
    let configuration = NSImage.SymbolConfiguration(pointSize: height, weight: .regular)
    guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: "TouchGuard")?
        .withSymbolConfiguration(configuration) else {
        FileHandle.standardError.write(Data("No system symbol named \(symbolName)\n".utf8))
        exit(1)
    }
    // Symbol images carry their own aspect ratio; scale by height so the hand
    // keeps its proportions at every canvas size.
    let scale = height / symbol.size.height
    let size = NSSize(width: symbol.size.width * scale, height: height)

    let tinted = NSImage(size: size, flipped: false) { rect in
        symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    return tinted
}

func render(pixels: Int) -> Data {
    let side = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { exit(1) }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let plateSide = side * plateRatio
    let plate = NSRect(
        x: (side - plateSide) / 2, y: (side - plateSide) / 2,
        width: plateSide, height: plateSide
    )
    let radius = side * radiusRatio
    let box = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)
    box.addClip()
    NSGradient(starting: topColor, ending: bottomColor)?
        .draw(in: plate, angle: -90)

    let hand = glyph(height: side * glyphRatio)
    let origin = NSPoint(x: plate.midX - hand.size.width / 2, y: plate.midY - hand.size.height / 2)
    hand.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    return png
}

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/Resources/AppIcon.icns"

let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("TouchGuard-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try render(pixels: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(pixels: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)

guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
print("Wrote \(output)")
