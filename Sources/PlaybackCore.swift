import Foundation

struct SaverSettings: Codable, Equatable {
    static let currentVersion = 1
    var version = currentVersion
    var folders: [String: Data] = [:]
    var duration: Double = 5
    var fade: Double = 1.5
    var maximumZoom: Double = 1.2
    var random = true
    var recursive = false

    var validationMessage: String? {
        guard duration.isFinite, (2...120).contains(duration) else { return "每张间隔须为 2–120 秒。" }
        guard fade.isFinite, (0...min(5, duration / 2)).contains(fade) else { return "过渡须为 0–min(5, 间隔/2) 秒。" }
        guard maximumZoom.isFinite, (1.1...1.2).contains(maximumZoom) else { return "缩放上限须为 1.10–1.20。" }
        return nil
    }
    static func load(from data: Data?, legacyFolders: [String: Data] = [:]) -> SaverSettings {
        guard let data, var value = try? JSONDecoder().decode(Self.self, from: data),
              value.version == currentVersion else {
            var fallback = Self(); fallback.folders = legacyFolders; return fallback
        }
        if value.validationMessage != nil {
            let folders = value.folders; value = Self(); value.folders = folders
        }
        return value
    }
    func encoded() throws -> Data {
        guard validationMessage == nil, version == Self.currentVersion else { throw CatalogError.invalidSettings }
        return try JSONEncoder().encode(self)
    }
}

enum CatalogError: Error { case cancelled, invalidSettings, notDirectory }

struct PhotoEntry: Equatable, Hashable {
    let relativePath: String
    let url: URL
}

enum PhotoCatalog {
    static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp"]
    // A fixed locale and literal tie-break make ordering stable across user locales.
    static func ordered(_ entries: [PhotoEntry]) -> [PhotoEntry] {
        entries.sorted {
            let order = $0.relativePath.compare($1.relativePath, options: [.numeric, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            return order == .orderedSame ? $0.relativePath.utf8.lexicographicallyPrecedes($1.relativePath.utf8) : order == .orderedAscending
        }
    }
    // Caller owns scoped access and runs this synchronous operation on its worker queue.
    static func scan(root: URL, recursive: Bool, cancelled: () -> Bool) throws -> [PhotoEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey, .isPackageKey, .isHiddenKey]
        guard try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw CatalogError.notDirectory }
        var entries: [PhotoEntry] = []
        var pending: [(URL, String)] = [(root, "")]
        while let (directory, prefix) = pending.popLast() {
            if cancelled() { throw CatalogError.cancelled }
            // Failure of the root must reach the UI; unreadable subdirectories are skipped.
            let children: [URL]
            do { children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) }
            catch { if prefix.isEmpty { throw error }; continue }
            for url in children {
                if cancelled() { throw CatalogError.cancelled }
                guard let info = try? url.resourceValues(forKeys: keys), info.isHidden != true,
                      info.isSymbolicLink != true, info.isAliasFile != true, info.isPackage != true else { continue }
                let relative = prefix + url.lastPathComponent
                if info.isDirectory == true {
                    if recursive { pending.append((url, relative + "/")) }
                } else if info.isRegularFile == true, extensions.contains(url.pathExtension.lowercased()) {
                    entries.append(PhotoEntry(relativePath: relative, url: url))
                }
            }
        }
        return ordered(entries)
    }
}

// Deterministic generator for reproducible tests; each live session gets its own seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

struct PlaybackQueue {
    private var generator: SeededGenerator
    private var round: [PhotoEntry] = []
    private var cursor = 0
    private var rejected = Set<String>()
    private var previous: String?
    private var beforeCandidate: String?
    var needsSnapshot: Bool { cursor >= round.count }
    init(seed: UInt64) { generator = SeededGenerator(seed: seed) }

    // Only replace at a round boundary. A changed catalog never mutates an in-flight round.
    mutating func beginRound(snapshot: [PhotoEntry], random: Bool) {
        precondition(needsSnapshot)
        var seen = Set<String>()
        round = PhotoCatalog.ordered(snapshot.filter { !rejected.contains($0.relativePath) && seen.insert($0.relativePath).inserted })
        if random {
            round.shuffle(using: &generator)
            if round.count > 1, round.first?.relativePath == previous {
                round.swapAt(0, Int.random(in: 1..<round.count, using: &generator))
            }
        }
        cursor = 0
    }
    mutating func next() -> PhotoEntry? {
        while cursor < round.count {
            let entry = round[cursor]; cursor += 1
            guard !rejected.contains(entry.relativePath) else { continue }
            beforeCandidate = previous
            previous = entry.relativePath
            return entry
        }
        return nil
    }
    mutating func reject(_ entry: PhotoEntry) {
        rejected.insert(entry.relativePath)
        if previous == entry.relativePath { previous = beforeCandidate }
    }
}
