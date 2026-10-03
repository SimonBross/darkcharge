// Draws the DarkCharge app icon: an aluminum MagSafe plug with its LED off,
// on a night-blue tile. Usage: swift make_icon.swift <out.png>  (renders 1024×1024)

import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    // macOS app icon tile: 824pt rounded square centered in 1024.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.black.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.21, blue: 0.34, alpha: 1),
               ending: NSColor(srgbRed: 0.04, green: 0.06, blue: 0.12, alpha: 1))!
        .draw(in: tilePath, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()

    // Same geometry as the menu bar icon (an 18-unit grid), scaled up and centered.
    let unit: CGFloat = 36
    let origin = NSPoint(x: 512 - 10.25 * unit, y: 512 - 9 * unit)
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: origin.x + x * unit, y: origin.y + y * unit, width: w * unit, height: h * unit)
    }

    // Cable runs in from the tile's left edge.
    let cableRect = r(3.5, 7.6, 5, 2.8)
    let cable = NSBezierPath(rect: NSRect(x: tile.minX, y: cableRect.minY,
                                          width: cableRect.maxX - tile.minX, height: cableRect.height))
    NSGradient(colors: [NSColor(white: 0.93, alpha: 1), NSColor(white: 0.72, alpha: 1), NSColor(white: 0.86, alpha: 1)])!
        .draw(in: cable, angle: -90)

    // Plug body: rounded on the cable side, square on the magnetic face.
    let b = r(8, 2, 8.5, 14)
    let radius = 1 * unit
    let body = NSBezierPath()
    body.move(to: NSPoint(x: b.maxX, y: b.minY))
    body.line(to: NSPoint(x: b.maxX, y: b.maxY))
    body.appendArc(from: NSPoint(x: b.minX, y: b.maxY), to: NSPoint(x: b.minX, y: b.minY), radius: radius)
    body.appendArc(from: NSPoint(x: b.minX, y: b.minY), to: NSPoint(x: b.maxX, y: b.minY), radius: radius)
    body.close()

    NSGraphicsContext.saveGraphicsState()
    let bodyShadow = NSShadow()
    bodyShadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    bodyShadow.shadowBlurRadius = 24
    bodyShadow.shadowOffset = NSSize(width: 0, height: -10)
    bodyShadow.set()
    NSColor(white: 0.8, alpha: 1).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(white: 0.97, alpha: 1), NSColor(white: 0.80, alpha: 1), NSColor(white: 0.68, alpha: 1)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: body, angle: -90)

    // Darker magnetic face along the right edge.
    NSColor(white: 0.45, alpha: 1).setFill()
    NSRect(x: b.maxX - 0.45 * unit, y: b.minY, width: 0.45 * unit, height: b.height).fill()

    // The LED, switched off: a dark, slightly recessed dot.
    let led = NSBezierPath(ovalIn: r(11.25 - 0.25, 8 - 0.25, 2.5, 2.5))
    NSColor(srgbRed: 0.10, green: 0.12, blue: 0.16, alpha: 1).setFill()
    led.fill()
    NSColor(white: 0.55, alpha: 1).setStroke()
    led.lineWidth = 4
    led.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
