#!/usr/bin/env swift
//
// make-icon.swift — render the app icon at every macOS size.
//
// Draws the SF Symbol "radio" in white on a rounded-rect tile with a soft
// gradient. Runs under plain `swift`; the Makefile runs
// `iconutil -c icns build/AppIcon.iconset` on the PNGs this writes.

import AppKit

let iconsetDir = "build/AppIcon.iconset"
try? FileManager.default.createDirectory(
    atPath: iconsetDir, withIntermediateDirectories: true)

// (filename, pixel dimension) — the set iconutil expects.
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func draw(into ctx: CGContext, size s: CGFloat) {
    // Background tile — rounded rect with a soft vertical gradient.
    let inset = s * 0.06
    let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let corner = s * 0.22
    let tilePath = CGPath(roundedRect: tile, cornerWidth: corner, cornerHeight: corner, transform: nil)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.30, green: 0.46, blue: 0.95, alpha: 1),
            CGColor(red: 0.16, green: 0.28, blue: 0.78, alpha: 1),
        ] as CFArray,
        locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    drawGlyph(into: ctx, tile: tile)
}

func drawGlyph(into ctx: CGContext, tile: CGRect) {
    // Render a white SF Symbol "radio" centered in the tile.
    let nsctx = NSGraphicsContext(cgContext: ctx, flipped: false)
    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = nsctx
    defer { NSGraphicsContext.current = previous }

    let symbolConfig = NSImage.SymbolConfiguration(
        pointSize: tile.height * 0.55,
        weight: .medium
    ).applying(NSImage.SymbolConfiguration(paletteColors: [.white]))

    guard let radio = NSImage(systemSymbolName: "radio", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)
    else {
        fatalError("Unable to load SF Symbol 'radio' for the app icon")
    }

    let size = radio.size
    let rect = CGRect(
        x: tile.midX - size.width / 2,
        y: tile.midY - size.height / 2,
        width: size.width,
        height: size.height)

    radio.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
}

for (name, px) in variants {
    let dim = CGFloat(px)
    guard let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { continue }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    draw(into: ctx, size: dim)
    guard let image = ctx.makeImage() else { continue }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(iconsetDir)/\(name)"))
}

print("✓ wrote \(variants.count) icons to \(iconsetDir)")
