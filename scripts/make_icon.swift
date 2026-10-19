import AppKit
// A native vector drawing, rasterized into the app icon sizes by this script.
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSGradient(starting: NSColor(calibratedRed: 0.04, green: 0.58, blue: 0.58, alpha: 1), ending: NSColor(calibratedRed: 0.03, green: 0.29, blue: 0.43, alpha: 1))!.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), angle: -45)
NSColor.white.withAlphaComponent(0.18).setFill()
NSBezierPath(roundedRect: NSRect(x: 165, y: 230, width: 610, height: 620), xRadius: 100, yRadius: 100).fill()
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 245, y: 165, width: 610, height: 620), xRadius: 100, yRadius: 100).fill()
let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
("S" as NSString).draw(in: NSRect(x: 255, y: 195, width: 590, height: 560), withAttributes: [.font: NSFont.systemFont(ofSize: 465, weight: .bold), .foregroundColor: NSColor(calibratedRed: 0.03, green: 0.42, blue: 0.47, alpha: 1), .paragraphStyle: paragraph])
NSColor(calibratedRed: 1, green: 0.76, blue: 0.25, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 730, y: 705, width: 145, height: 145)).fill()
image.unlockFocus()
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [("20x20", 2), ("20x20", 3), ("29x29", 2), ("29x29", 3), ("40x40", 2), ("40x40", 3), ("60x60", 2), ("60x60", 3), ("1024x1024", 1)]
var entries: [[String: String]] = []
for (size, scale) in sizes {
    let points = Int(size.split(separator: "x")[0])!; let pixels = points * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels)); NSGraphicsContext.restoreGraphicsState()
    let name = "icon-\(points)-\(scale).png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    entries.append(["idiom": points == 1024 ? "ios-marketing" : "iphone", "size": size, "scale": "\(scale)x", "filename": name])
}
let data = try JSONSerialization.data(withJSONObject: ["images": entries, "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys])
try data.write(to: folder.appendingPathComponent("Contents.json"))
