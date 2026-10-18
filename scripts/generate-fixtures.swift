import AppKit
import ImageIO
import UniformTypeIdentifiers

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for (route, width, height, color) in [("H", 1600, 900, NSColor.systemBlue), ("V", 900, 1600, NSColor.systemOrange)] {
    let directory = destination.appendingPathComponent(route, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    color.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSColor.white.setStroke()
    let edge = NSBezierPath(rect: NSRect(x: 12, y: 12, width: width - 24, height: height - 24))
    edge.lineWidth = 16; edge.stroke()
    for x in stride(from: 80, to: width, by: 80) {
        NSColor.white.withAlphaComponent(0.2).setFill()
        NSRect(x: x, y: 0, width: 3, height: height).fill()
    }
    for (text, y) in [("SYNTHETIC \(route)", height - 150), ("\(route == "H" ? "LANDSCAPE / BLUE" : "PORTRAIT / ORANGE")", 150), ("MIT · Multiscreen Saver G1", 60)] {
        (text as NSString).draw(at: NSPoint(x: 60, y: y), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 48), .foregroundColor: NSColor.white])
    }
    image.unlockFocus()
    var rect = NSRect(origin: .zero, size: image.size)
    guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
          let out = CGImageDestinationCreateWithURL(directory.appendingPathComponent("\(route)-marker.png") as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("fixture generation failed") }
    CGImageDestinationAddImage(out, cg, nil)
    precondition(CGImageDestinationFinalize(out))
    print("generated synthetic \(route): \(cg.width)x\(cg.height)")
}
for (index, screen) in NSScreen.screens.enumerated() {
    print("screen \(index): \(Int(screen.frame.width))x\(Int(screen.frame.height)) scale=\(screen.backingScaleFactor)")
}
