import AppKit

let directory = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
let background = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 215, yRadius: 215)
NSGradient(starting: NSColor(calibratedWhite: 0.20, alpha: 1), ending: NSColor(calibratedWhite: 0.07, alpha: 1))!.draw(in: background, angle: -90)
let shadow = NSShadow(); shadow.shadowBlurRadius = 32; shadow.shadowOffset = NSSize(width: 0, height: -20); shadow.shadowColor = .black.withAlphaComponent(0.6)
NSGraphicsContext.saveGraphicsState(); shadow.set()
let base = NSBezierPath(roundedRect: NSRect(x: 215, y: 220, width: 594, height: 580), xRadius: 105, yRadius: 105)
NSColor(calibratedRed: 0.62, green: 0.34, blue: 0.18, alpha: 1).setFill(); base.fill()
NSGraphicsContext.restoreGraphicsState()
let key = NSBezierPath(roundedRect: NSRect(x: 215, y: 285, width: 594, height: 535), xRadius: 105, yRadius: 105)
NSGradient(starting: NSColor(calibratedRed: 1, green: 0.74, blue: 0.49, alpha: 1), ending: NSColor(calibratedRed: 0.93, green: 0.52, blue: 0.28, alpha: 1))!.draw(in: key, angle: -90)
let inset = NSBezierPath(roundedRect: NSRect(x: 262, y: 335, width: 500, height: 440), xRadius: 78, yRadius: 78)
NSColor.black.withAlphaComponent(0.10).setStroke(); inset.lineWidth = 3; inset.stroke()
let text: NSString = "C"
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 330, weight: .bold), .foregroundColor: NSColor(calibratedWhite: 0.13, alpha: 1)]
let textSize = text.size(withAttributes: attributes)
text.draw(at: NSPoint(x: (1024-textSize.width)/2, y: 345), withAttributes: attributes)
image.unlockFocus()
let sizes = [16,32,64,128,256,512,1024]
for size in sizes {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    if size <= 512 { try data.write(to: URL(fileURLWithPath: "\(directory)/icon_\(size)x\(size).png")) }
    if size >= 32 { try data.write(to: URL(fileURLWithPath: "\(directory)/icon_\(size/2)x\(size/2)@2x.png")) }
}
