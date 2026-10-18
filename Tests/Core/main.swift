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
