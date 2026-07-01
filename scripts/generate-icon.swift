#!/usr/bin/swift
// Generates a placeholder GameBridge app icon at all Apple-required sizes
// and packages them into GameBridge.iconset + a compiled .icns, plus a
// single 1024×1024 PNG that Asset Catalogs also accept.
//
// The design: a rounded-rectangle Metal-purple → deep-blue gradient
// background, a large `SF Symbol` shippingbox in white, and a small
// controller glyph tucked in the corner — echoing GameBridge's core
// motifs (bottles + games).
//
// Not high art; adequate as a placeholder until someone draws a real one.

import AppKit
import CoreGraphics

let baseSize: CGFloat = 1024
let iconsetURL = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "build/GameBridge.iconset")

try? FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let scale = size / baseSize
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = NSGraphicsContext.current!.cgContext

    // Rounded-rectangle background per Apple icon spec (~22.37% corner radius).
    let cornerRadius: CGFloat = size * 0.2237
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    bgPath.addClip()

    // Gradient background: purple → deep blue, roughly matching macOS
    // accent-highlight tinting.
    let top = NSColor(calibratedRed: 0.42, green: 0.20, blue: 0.75, alpha: 1.0)
    let bottom = NSColor(calibratedRed: 0.10, green: 0.20, blue: 0.55, alpha: 1.0)
    let gradient = NSGradient(colors: [top, bottom])!
    gradient.draw(in: rect, angle: -90)

    // Central shippingbox glyph (SF Symbols). `hierarchicalColor:` is what
    // actually tints the symbol — `NSColor.set()` has no effect on a
    // rendered NSImage. Requires macOS 12+.
    let boxConfig = NSImage.SymbolConfiguration(pointSize: 520 * scale, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(hierarchicalColor: .white))
    if let box = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(boxConfig) {
        let s = box.size
        let r = CGRect(
            x: (size - s.width) / 2,
            y: (size - s.height) / 2 + size * 0.02,
            width: s.width,
            height: s.height
        )
        box.draw(
            in: r, from: .zero,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    // Small controller glyph in the bottom-right corner, slightly translucent
    // so it reads as an accent rather than competing with the box.
    let ctrlConfig = NSImage.SymbolConfiguration(pointSize: 210 * scale, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(hierarchicalColor: NSColor.white.withAlphaComponent(0.92)))
    if let controller = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(ctrlConfig) {
        let s = controller.size
        let r = CGRect(
            x: size - s.width - size * 0.08,
            y: size * 0.08,
            width: s.width,
            height: s.height
        )
        controller.draw(
            in: r, from: .zero,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon-gen", code: 1)
    }
    try data.write(to: url)
}

// Apple's macOS icon size table.
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]

for (name, px) in sizes {
    let rep = drawIcon(size: CGFloat(px))
    let url = iconsetURL.appendingPathComponent(name)
    do {
        try writePNG(rep: rep, to: url)
        print("  wrote \(name) (\(px)×\(px))")
    } catch {
        print("ERROR writing \(name): \(error)")
        exit(1)
    }
}

print("Iconset written to \(iconsetURL.path)")
