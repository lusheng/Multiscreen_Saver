import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("multiscreen-core-\(UUID().uuidString)")
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
func file(_ path: String) throws {
    let url = root.appendingPathComponent(path)
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data([1, 2, 3]).write(to: url)
}
for p in ["10.JPG", "2.png", "A.heic", "a.webp", ".hidden.png", "no.txt", "子目录/2.png", "子目录/1.jpeg", "Hidden.app/inside.png"] { try file(p) }
try fm.createSymbolicLink(atPath: root.appendingPathComponent("loop").path, withDestinationPath: root.path)
try fm.createSymbolicLink(atPath: root.appendingPathComponent("link.png").path, withDestinationPath: root.appendingPathComponent("2.png").path)
let flat = try PhotoCatalog.scan(root: root, recursive: false, cancelled: { false })
check(flat.map(\.relativePath) == ["2.png", "10.JPG", "A.heic", "a.webp"], "natural order/filter")
let deep = try PhotoCatalog.scan(root: root, recursive: true, cancelled: { false })
check(deep.count == 6 && deep.contains { $0.relativePath == "子目录/2.png" }, "recursive snapshot")
do { _ = try PhotoCatalog.scan(root: root, recursive: true, cancelled: { true }); fatalError("must cancel") } catch CatalogError.cancelled { }
let emptyRoot = root.appendingPathComponent("empty")
try fm.createDirectory(at: emptyRoot, withIntermediateDirectories: false)
let empty = try PhotoCatalog.scan(root: emptyRoot, recursive: true, cancelled: { false })
check(empty.isEmpty, "empty directory")
for size in [0, 1, 2, 6] {
    let snapshot = Array(deep.prefix(size))
    for seed in 0..<100 {
        var queue = PlaybackQueue(seed: UInt64(seed)); var last: String?
        for _ in 0..<20 {
            queue.beginRound(snapshot: snapshot, random: true)
            var round: [String] = []
            while let e = queue.next() { round.append(e.relativePath) }
            check(Set(round).count == size && round.count == size, "one occurrence per round")
            if size > 1 { check(round.first != last, "cross round adjacency") }
            last = round.last
        }
    }
}
var q = PlaybackQueue(seed: 42)
q.beginRound(snapshot: deep, random: false)
var sequence: [PhotoEntry] = []
while let e = q.next() { sequence.append(e) }
check(sequence == deep, "sequential ordering")
q.reject(deep[0]);q.beginRound(snapshot: deep, random: false)
check(q.next() == deep[1], "bad file quarantine")
var a = PlaybackQueue(seed: 4), b = PlaybackQueue(seed: 4)
a.beginRound(snapshot: deep, random: true);b.beginRound(snapshot: deep, random: true)
let first = a.next(); _ = a.next();check(b.next() == first, "session independence")
var settings = SaverSettings();settings.folders = ["H": Data([4]), "V": Data([5])]
let encoded = try settings.encoded()
check(SaverSettings.load(from: encoded) == settings, "settings round trip")
settings.duration = 2;settings.fade = 1.5
check(settings.validationMessage != nil, "invalid D/F rejected")
settings.fade = 1;check(settings.validationMessage == nil, "boundary accepted")
settings.maximumZoom = .nan;check(settings.validationMessage != nil, "NaN rejected")
check(SaverSettings.load(from: Data([0]), legacyFolders: ["H": Data([3])]).folders["H"] == Data([3]), "legacy fallback")
let invalid = Data("{\"version\":1,\"folders\":{},\"duration\":-1,\"fade\":3,\"maximumZoom\":1.2,\"random\":true,\"recursive\":false}".utf8)
check(SaverSettings.load(from: invalid).duration == 5, "corrupt numeric defaults")
print("PASS: settings, catalog filters/cancellation, 8000 seeded rounds, sequential order, quarantine and session isolation")
var geometryRNG = SeededGenerator(seed: 917)
for i in 0..<10_000 {
    let viewport = i % 2 == 0 ? CGSize(width: 2560, height: 1440) : CGSize(width: 1440, height: 2560)
    let size = CGSize(width: Int.random(in: 1...30000, using: &geometryRNG), height: Int.random(in: 1...30000, using: &geometryRNG))
    let path = KenBurnsPath(image: size, viewport: viewport, backingScale: 2, maximumZoom: Double.random(in: 1.1...1.2, using: &geometryRNG), generator: &geometryRNG)
    for j in 0...100 {
        let r = path.rect(progress: Double(j) / 100)
        check(r.minX <= -0.999 && r.minY <= -0.999 && r.maxX >= viewport.width + 0.999 && r.maxY >= viewport.height + 0.999, "coverage including sampling margin")
        check(abs(r.width / r.height - size.width / size.height) < 0.00001, "aspect preserved")
    }
}
print("PASS: 10000 seeded geometry paths, 101 samples each, coverage and aspect invariants")
for size in [CGSize(width: 1, height: 1), CGSize(width: 1, height: 100000), CGSize(width: 100000, height: 1), CGSize(width: 2560, height: 1440)] {
    for viewport in [CGSize(width: 2560, height: 1440), CGSize(width: 1440, height: 2560), CGSize(width: 1, height: 1)] {
        for scale in [CGFloat(1), CGFloat(2)] {
            let path = KenBurnsPath(image: size, viewport: viewport, backingScale: scale, maximumZoom: 1.1, generator: &geometryRNG)
            for t in [-1.0, 0, 0.5, 1, 2] {
                let rect = path.rect(progress: t)
                check(rect.minX <= 0 && rect.minY <= 0 && rect.maxX >= viewport.width && rect.maxY >= viewport.height, "fixed extremes and clamped progress")
            }
        }
    }
}
var changed = PlaybackQueue(seed: 3)
changed.beginRound(snapshot: Array(deep.prefix(2)), random: false)
_ = changed.next(); _ = changed.next()
changed.beginRound(snapshot: [deep[2]], random: false)
check(changed.next() == deep[2] && changed.next() == nil, "round snapshot replacement")
var quarantine = PlaybackQueue(seed: 1)
quarantine.beginRound(snapshot: deep, random: false)
while let item = quarantine.next() { quarantine.reject(item) }
quarantine.beginRound(snapshot: deep, random: true)
check(quarantine.next() == nil, "all bad files terminate")
print("PASS: fixed geometric extremes, snapshot replacement and all-bad termination")
func timing(_ t: Double, _ current: Double?, _ incoming: Double?, _ ready: Bool = true, _ fade: Double = 1.5) -> PlaybackTiming {
    PlaybackTiming.evaluate(now: t, currentStart: current, incomingStart: incoming, ready: ready, duration: 5, fade: fade)
}
check(!timing(4.999,0,nil).startNext && timing(5,0,nil).startNext, "5-second start interval")
check(!timing(6.499,0,5).finishIncoming && !timing(6.499,0,5).startNext, "two moving images through overlap")
check(timing(6.5,0,5).finishIncoming && !timing(6.5,0,5).startNext, "1.5-second transition end")
check(timing(10,5,nil).startNext, "next interval starts at incoming start, not transition end")
check(!timing(7,0,nil,false).startNext && timing(7,0,nil,true).startNext, "late decode preserves current until ready")
check(!timing(10,7,nil).startNext && timing(12,7,nil).startNext, "delayed transition rebases time")
check(timing(5,0,nil,true,0).startNext, "zero fade hard cut")
print("PASS: default timeline, overlap, zero fade, delayed decode and rebased interval")
