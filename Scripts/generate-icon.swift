import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let tile = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 212, yRadius: 212)
NSGradient(starting: NSColor(red: 0.31, green: 0.28, blue: 0.78, alpha: 1),
           ending: NSColor(red: 0.56, green: 0.52, blue: 0.98, alpha: 1))!.draw(in: tile, angle: 75)
for (x, y) in [(300.0, 428.0), (512.0, 638.0), (724.0, 522.0)] {
    NSColor.white.withAlphaComponent(0.23).setFill()
    NSBezierPath(roundedRect: NSRect(x: x - 14, y: 254, width: 28, height: 516), xRadius: 14, yRadius: 14).fill()
    NSColor.white.withAlphaComponent(0.85).setFill()
    NSBezierPath(roundedRect: NSRect(x: x - 14, y: 254, width: 28, height: y - 254), xRadius: 14, yRadius: 14).fill()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.17)
    shadow.shadowBlurRadius = 16
    shadow.shadowOffset = NSSize(width: 0, height: -6)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: x - 67, y: y - 39, width: 134, height: 78), xRadius: 28, yRadius: 28).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor(red: 0.42, green: 0.38, blue: 0.85, alpha: 0.4).setFill()
    NSBezierPath(roundedRect: NSRect(x: x - 36, y: y - 3, width: 72, height: 6), xRadius: 3, yRadius: 3).fill()
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
