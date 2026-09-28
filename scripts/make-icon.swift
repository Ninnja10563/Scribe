import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
    NSColor(srgbRed: 0.12, green: 0.17, blue: 0.23, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 200, yRadius: 200).fill()
    NSColor(srgbRed: 0.61, green: 0.70, blue: 0.76, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 230, y: 173, width: 540, height: 675), xRadius: 24, yRadius: 24).fill()
    NSColor(srgbRed: 0.98, green: 0.98, blue: 0.96, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 272, y: 143, width: 540, height: 675), xRadius: 24, yRadius: 24).fill()
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 380, weight: .semibold), .foregroundColor: NSColor(srgbRed: 0.12, green: 0.17, blue: 0.23, alpha: 1)]
    let letter = "S" as NSString; let size = letter.size(withAttributes: attrs)
    letter.draw(at: NSPoint(x: 542 - size.width / 2, y: 327), withAttributes: attrs)
    NSColor(srgbRed: 0.61, green: 0.70, blue: 0.76, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 374, y: 280, width: 330, height: 16)).fill()
    NSBezierPath(rect: NSRect(x: 374, y: 230, width: 230, height: 16)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination).appendingPathComponent(name + ".png"))
}
