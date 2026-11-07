#!/usr/bin/env swift

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.png>\n".utf8))
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let side = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side,
    pixelsHigh: side,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    exit(1)
}
rep.size = NSSize(width: side, height: side)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let bounds = NSRect(x: 0, y: 0, width: side, height: side)

// Deep indigo background.
if let background = NSGradient(colors: [
    NSColor(srgbRed: 0.20, green: 0.26, blue: 0.55, alpha: 1),
    NSColor(srgbRed: 0.05, green: 0.06, blue: 0.12, alpha: 1)
]) {
    background.draw(in: bounds, angle: -65)
}

// Specular highlight in the upper-left. Draw it radially over the whole
// canvas so its bounding box cannot leave a visible seam.
if let glow = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.32),
    NSColor.white.withAlphaComponent(0.0)
]) {
    let center = NSPoint(x: bounds.width * 0.18, y: bounds.height * 0.82)
    glow.draw(
        fromCenter: center,
        radius: 0,
        toCenter: center,
        radius: bounds.width * 0.78,
        options: []
    )
}

// Translucent glass slab.
let slabRect = bounds.insetBy(dx: 88, dy: 88)
let slab = NSBezierPath(roundedRect: slabRect, xRadius: 184, yRadius: 184)
NSColor.white.withAlphaComponent(0.10).setFill()
slab.fill()
NSColor.white.withAlphaComponent(0.24).setStroke()
slab.lineWidth = 4
slab.stroke()

// White barcode card with a soft shadow.
let cardRect = bounds.insetBy(dx: 182, dy: 262)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
shadow.shadowBlurRadius = 42
shadow.shadowOffset = NSSize(width: 0, height: -16)
NSGraphicsContext.saveGraphicsState()
shadow.set()
let card = NSBezierPath(roundedRect: cardRect, xRadius: 74, yRadius: 74)
NSColor.white.setFill()
card.fill()
NSGraphicsContext.restoreGraphicsState()

// Barcode bars.
let barWidths: [CGFloat] = [26, 12, 30, 10, 18, 34, 12, 22, 12, 30, 18, 10, 26, 12, 34, 10, 22]
let gap: CGFloat = 10
let totalWidth = barWidths.reduce(0, +) + CGFloat(barWidths.count - 1) * gap
let barsRect = cardRect.insetBy(dx: 70, dy: 150)
var barX = cardRect.midX - totalWidth / 2
NSColor.black.setFill()
for width in barWidths {
    NSBezierPath(rect: NSRect(x: barX, y: barsRect.minY, width: width, height: barsRect.height)).fill()
    barX += width + gap
}

// Small strokes under the bars suggest the human-readable digits.
let captionWidths: [CGFloat] = [14, 18, 12, 20, 16, 12, 18, 14]
let captionGap: CGFloat = 12
let captionTotal = captionWidths.reduce(0, +) + CGFloat(captionWidths.count - 1) * captionGap
var captionX = cardRect.midX - captionTotal / 2
let captionY = barsRect.minY - 44
NSColor.black.withAlphaComponent(0.75).setFill()
for width in captionWidths {
    NSBezierPath(rect: NSRect(x: captionX, y: captionY, width: width, height: 12)).fill()
    captionX += width + captionGap
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    exit(1)
}

do {
    try png.write(to: outputURL)
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
