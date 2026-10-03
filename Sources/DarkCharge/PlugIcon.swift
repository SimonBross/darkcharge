import AppKit

// Menu bar icon: a MagSafe 3 plug seen from above, cable coming in from the left.
// While the LED is lit, a dot is cut out where the LED sits.
func plugIcon(ledLit: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 3.5, y: 7.6, width: 5, height: 2.8), xRadius: 0.5, yRadius: 0.5).fill()

        // Slightly rounded on the cable side, square on the magnetic face.
        let body = NSBezierPath()
        body.move(to: NSPoint(x: 16.5, y: 2))
        body.line(to: NSPoint(x: 16.5, y: 16))
        body.appendArc(from: NSPoint(x: 8, y: 16), to: NSPoint(x: 8, y: 2), radius: 1)
        body.appendArc(from: NSPoint(x: 8, y: 2), to: NSPoint(x: 16.5, y: 2), radius: 1)
        body.close()
        if ledLit {
            body.append(NSBezierPath(ovalIn: NSRect(x: 11.25, y: 8, width: 2, height: 2)))
            body.windingRule = .evenOdd
        }
        body.fill()
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "DarkCharge"
    return image
}
