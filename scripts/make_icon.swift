import AppKit
import ImageIO

// Package the approved artwork into opaque iPhone icon assets.
// Usage: swift scripts/make_icon.swift App/Assets.xcassets/AppIcon.appiconset
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sourceURL = URL(fileURLWithPath: "App/Artwork/beer-steins.png")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil), artwork.width == artwork.height else {
    fatalError("Expected square source artwork at App/Artwork/beer-steins.png")
}
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [("20x20", 2), ("20x20", 3), ("29x29", 2), ("29x29", 3), ("40x40", 2), ("40x40", 3), ("60x60", 2), ("60x60", 3), ("1024x1024", 1)]
var entries: [[String: String]] = []
for (size, scale) in sizes {
    let points = Int(size.split(separator: "x")[0])!; let pixels = points * scale
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.interpolationQuality = .high
    context.draw(artwork, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    let name = "icon-\(points)-\(scale).png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    entries.append(["idiom": points == 1024 ? "ios-marketing" : "iphone", "size": size, "scale": "\(scale)x", "filename": name])
}
let data = try JSONSerialization.data(withJSONObject: ["images": entries, "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys])
try data.write(to: folder.appendingPathComponent("Contents.json"))
