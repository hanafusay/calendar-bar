import AppKit
import Foundation

let folder = URL(fileURLWithPath: ".build/CalendarBar.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let symbol = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Calendar Bar")!
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let side = CGFloat(pixels)
        let tile = NSBezierPath(roundedRect: NSRect(x: side * 0.05, y: side * 0.05, width: side * 0.9, height: side * 0.9), xRadius: side * 0.2, yRadius: side * 0.2)
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        tile.fill()
        NSColor.systemBlue.set()
        symbol.draw(in: NSRect(x: side * 0.23, y: side * 0.23, width: side * 0.54, height: side * 0.54))
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = bitmap.representation(using: .png, properties: [:])!
        precondition(!data.isEmpty)
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
