import AppKit

// One vector master for the Dock icon, sidebar mark, scan illustration, and exports.
enum LogoArtwork {
    static let mark = image(size: 256)
    static func image(size: Int) -> NSImage {
        let pixels = NSSize(width: size, height: size)
        let image = NSImage(size: pixels)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        let tile = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 213, yRadius: 213)
        NSGradient(starting: NSColor(red: 0.39, green: 0.24, blue: 0.71, alpha: 1), ending: NSColor(red: 0.12, green: 0.08, blue: 0.27, alpha: 1))!.draw(in: tile, angle: 62)
        NSColor.white.withAlphaComponent(0.16).setStroke(); tile.lineWidth = 3; tile.stroke()
        let glow = NSBezierPath(ovalIn: NSRect(x: 200, y: 195, width: 624, height: 624))
        NSColor(red: 0.48, green: 0.95, blue: 0.80, alpha: 0.06).setFill(); glow.fill()
        let ring = NSBezierPath()
        ring.appendArc(withCenter: NSPoint(x: 500, y: 520), radius: 232, startAngle: 30, endAngle: 316, clockwise: false)
        ring.lineWidth = 76; ring.lineCapStyle = .round
        NSColor(red: 0.49, green: 0.96, blue: 0.81, alpha: 1).setStroke(); ring.stroke()
        let inner = NSBezierPath(); inner.move(to: NSPoint(x: 362, y: 470)); inner.curve(to: NSPoint(x: 580, y: 582), controlPoint1: NSPoint(x: 462, y: 410), controlPoint2: NSPoint(x: 486, y: 634))
        inner.lineWidth = 35; inner.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.92).setStroke(); inner.stroke()
        let star = NSBezierPath()
        for (index, point) in [NSPoint(x: 698, y: 331), NSPoint(x: 730, y: 410), NSPoint(x: 809, y: 442), NSPoint(x: 730, y: 474), NSPoint(x: 698, y: 553), NSPoint(x: 666, y: 474), NSPoint(x: 587, y: 442), NSPoint(x: 666, y: 410)].enumerated() {
            if index == 0 { star.move(to: point) } else { star.line(to: point) }
        }
        star.close(); NSColor.white.setFill(); star.fill()
        image.unlockFocus()
        return image
    }
}
