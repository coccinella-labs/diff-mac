import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.icns"
let outputURL = URL(fileURLWithPath: output)
let sourceURL = rootURL.appendingPathComponent("Sources/DIFFMac/Resources/AppIcon.png")
let iconsetURL = outputURL.deletingPathExtension().appendingPathExtension("iconset")

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
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

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    throw NSError(
        domain: "DIFFMacIcon",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Missing icon source: \(sourceURL.path)"]
    )
}

func resizedIcon(size: Int) throws -> Data {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    sourceImage.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: NSRect(origin: .zero, size: sourceImage.size),
        operation: .copy,
        fraction: 1
    )
    image.unlockFocus()

    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "DIFFMacIcon", code: 2)
    }
    return data
}

for (name, size) in specs {
    let data = try resizedIcon(size: size)
    try data.write(to: iconsetURL.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 {
    throw NSError(domain: "DIFFMacIcon", code: Int(process.terminationStatus))
}

try? FileManager.default.removeItem(at: iconsetURL)
