import Foundation
import ImageIO
import CoreGraphics

func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let png = CGImageSourceCreateWithURL(root.appendingPathComponent("quadrants.png") as CFURL, nil)!
let original = CGImageSourceCreateImageAtIndex(png, 0, nil)!
let heic = root.appendingPathComponent("quadrants.heic")
if let destination = CGImageDestinationCreateWithURL(heic as CFURL, "public.heic" as CFString, 1, nil) {
    CGImageDestinationAddImage(destination, original, nil)
    check(CGImageDestinationFinalize(destination), "HEIC fixture encode")
} else { fatalError("HEIC encoder unavailable; do not report format verified") }
for ext in ["jpg", "jpeg", "png", "webp", "heic"] {
    try autoreleasepool {
        let decoded = try ImageDecoder.decode(root.appendingPathComponent("quadrants.\(ext)"), viewport: CGSize(width: 2560, height: 1440), scale: 2, zoom: 1.2)
        check(decoded.image.width > 0 && decoded.image.height > 0, "format pixels")
        check(decoded.image.alphaInfo == .noneSkipLast, "opaque output")
        check(decoded.image.colorSpace?.name == CGColorSpace.sRGB, "sRGB output")
        check(decoded.image.bytesPerRow * decoded.image.height <= 32 * 1024 * 1024, "per image cache cap")
        print("decoded",ext,decoded.image.width,decoded.image.height)
    }
}
for o in 1...8 {
    try autoreleasepool {
        let decoded = try ImageDecoder.decode(root.appendingPathComponent("orientation-\(o).jpg"), viewport: CGSize(width: 400, height: 400), scale: 1, zoom: 1.2)
        check((decoded.image.width > decoded.image.height) == (o <= 4), "EXIF rotation aspect")
        let bytes = CFDataGetBytePtr(decoded.image.dataProvider!.data!)!
        let x = decoded.image.width / 4, y = decoded.image.height / 4
        let offset = y * decoded.image.bytesPerRow + x * 4
        let rgb = (Int(bytes[offset]), Int(bytes[offset+1]), Int(bytes[offset+2]))
        let expected: [(Int,Int,Int)] = [(255,0,0),(0,255,0),(0,0,255),(255,255,0),(255,0,0),(255,255,0),(0,0,255),(0,255,0)]
        let e = expected[o-1]
        check(abs(rgb.0-e.0)<15 && abs(rgb.1-e.1)<15 && abs(rgb.2-e.2)<15, "EXIF corner orientation \(o): \(rgb)")
    }
}
for ext in ["png","webp"] {
    try autoreleasepool {
        let photo = try ImageDecoder.decode(root.appendingPathComponent("transparent.\(ext)"), viewport: CGSize(width: 1600, height: 900), scale: 2, zoom: 1.2)
        check(photo.image.alphaInfo == .noneSkipLast && photo.image.width > photo.image.height, "transparent blur composite")
    }
}
do { _ = try ImageDecoder.decode(root.appendingPathComponent("broken.jpg"), viewport: CGSize(width: 100, height: 100), scale: 1, zoom: 1.2);fatalError("corrupt image accepted") } catch { }
check(ImageBudget.shared.current == 0, "decoded cache release")
print("PASS: five actual format decodes, EXIF 1–8 corner checks, opaque sRGB, transparent PNG/WebP, corrupt rejection, cache release")
let sessionRoot = root.appendingPathComponent("SessionFixture")
try FileManager.default.createDirectory(at: sessionRoot, withIntermediateDirectories: true)
for name in ["broken.jpg", "quadrants.png"] {
    let target = sessionRoot.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
    try FileManager.default.copyItem(at: root.appendingPathComponent(name), to: target)
}
let bookmark = try sessionRoot.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
var cfg = SaverSettings();cfg.random = false
let session = PhotoSession(settings: cfg, bookmark: bookmark, viewport: CGSize(width: 800, height: 600), scale: 1, seed: 9)
for _ in 0..<5 {
    var done = false
    session.requestNext { result in
        check(Thread.isMainThread, "result delivered on main")
        if case .failure(let error) = result { fatalError("good image after bad should remain playable: \(error)") }
        done = true
    }
    let deadline = Date(timeIntervalSinceNow: 5)
    while !done && Date() < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01)) }
    check(done, "bounded asynchronous completion")
}
session.cancel()
var cancelledCallback = false
let cancelledSession = PhotoSession(settings: cfg, bookmark: bookmark, viewport: CGSize(width: 800, height: 600), scale: 1, seed: 1)
cancelledSession.cancel()
cancelledSession.requestNext { _ in cancelledCallback = true }
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
check(!cancelledCallback, "cancelled generation must not write back")
check(ImageBudget.shared.current == 0, "asynchronous result cache released")
print("PASS: asynchronous session, bad-image quarantine across rounds, main delivery, cancelled writeback and cache release")
