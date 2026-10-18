import AppKit
import ImageIO
import CoreImage

// All scan/decode work is off the main thread and globally serial to bound transient buffers.
private let decodeWorker = DispatchQueue(label: "com.lusheng.MultiscreenSaver.decode", qos: .userInitiated)

final class DecodedPhoto {
    let image: CGImage
    private let bytes: Int
    init?(image: CGImage) {
        bytes = image.bytesPerRow * image.height
        guard ImageBudget.shared.reserve(bytes) else { return nil }
        self.image = image
    }
    deinit { ImageBudget.shared.release(bytes) }
}
final class ImageBudget {
    static let shared = ImageBudget()
    private let lock = NSLock()
    private var bytes = 0
    private(set) var peak = 0
    func reserve(_ amount: Int) -> Bool {
        lock.lock();defer { lock.unlock() }
        guard bytes + amount <= 256 * 1024 * 1024 else { return false }
        bytes += amount; peak = max(peak, bytes);return true
    }
    func release(_ amount: Int) { lock.lock();bytes -= amount;lock.unlock() }
    var current: Int { lock.lock();defer { lock.unlock() };return bytes }
}

enum ImageDecoder {
    static let pixelLimit = 8 * 1024 * 1024 // <=32 MiB per cached opaque image.
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let ci = CIContext(options: [.cacheIntermediates: false])
    private static func containsTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo { case .none, .noneSkipFirst, .noneSkipLast: return false; default: break }
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return true }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        return stride(from: 3, to: image.width * image.height * 4, by: 4).contains { bytes[$0] < 255 }
    }
    static func decode(_ url: URL, viewport: CGSize, scale: CGFloat, zoom: Double) throws -> DecodedPhoto {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? NSNumber,
              let h = props[kCGImagePropertyPixelHeight] as? NSNumber, w.doubleValue > 0, h.doubleValue > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let ratio = max(w.doubleValue / h.doubleValue, h.doubleValue / w.doubleValue)
        let requested = max(viewport.width, viewport.height) * scale * zoom
        let longest = max(1, min(8192, min(requested, sqrt(Double(pixelLimit) * ratio))))
        // HEIF uses its primary image; other formats use frame zero. ImageIO applies EXIF orientation.
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(longest)
        ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let hasAlpha = containsTransparency(thumb)
        var output = CGSize(width: thumb.width, height: thumb.height)
        if hasAlpha {
            let factor = min(scale * zoom, sqrt(Double(pixelLimit) / max(1, viewport.width * viewport.height)))
            output = CGSize(width: max(1, floor(viewport.width * factor)), height: max(1, floor(viewport.height * factor)))
        }
        let budgetScale = min(1, sqrt(Double(pixelLimit) / (output.width * output.height)))
        output = CGSize(width: max(1, floor(output.width * budgetScale)), height: max(1, floor(output.height * budgetScale)))
        guard output.width * output.height <= Double(pixelLimit),
              let context = CGContext(data: nil, width: Int(output.width), height: Int(output.height), bitsPerComponent: 8,
                                      bytesPerRow: Int(output.width) * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw CocoaError(.fileReadTooLarge) }
        let canvas = CGRect(origin: .zero, size: output)
        context.setFillColor(CGColor(gray: 0.12, alpha: 1));context.fill(canvas)
        if hasAlpha {
            let fill = max(output.width / CGFloat(thumb.width), output.height / CGFloat(thumb.height))
            let fit = min(output.width / CGFloat(thumb.width), output.height / CGFloat(thumb.height))
            let base = CIImage(cgImage: thumb).transformed(by: CGAffineTransform(scaleX: fill, y: fill))
                .transformed(by: CGAffineTransform(translationX: (output.width - CGFloat(thumb.width) * fill) / 2,
                                                 y: (output.height - CGFloat(thumb.height) * fill) / 2))
            let blurred = base.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 24]).cropped(to: canvas)
            guard let background = ci.createCGImage(blurred, from: canvas, format: .RGBA8, colorSpace: colorSpace) else { throw CocoaError(.fileReadCorruptFile) }
            context.draw(background, in: canvas)
            context.draw(thumb, in: CGRect(x: (output.width - CGFloat(thumb.width) * fit) / 2,
                                           y: (output.height - CGFloat(thumb.height) * fit) / 2,
                                           width: CGFloat(thumb.width) * fit, height: CGFloat(thumb.height) * fit))
        } else { context.draw(thumb, in: canvas) }
        guard let opaque = context.makeImage(), let result = DecodedPhoto(image: opaque) else { throw CocoaError(.fileReadTooLarge) }
        return result
    }
}

// All mutable catalog and queue state is confined to decodeWorker.
final class PhotoSession {
    private let identifier = String(UUID().uuidString.prefix(8))
    private let settings: SaverSettings
    private let bookmark: Data
    private let viewport: CGSize
    private let scale: CGFloat
    private let ticket = WorkTicket()
    private var queue: PlaybackQueue
    private var candidateCount = 0
    init(settings: SaverSettings, bookmark: Data, viewport: CGSize, scale: CGFloat, seed: UInt64) {
        self.settings = settings;self.bookmark = bookmark;self.viewport = viewport;self.scale = scale
        queue = PlaybackQueue(seed: seed)
    }
    func cancel() { ticket.cancel() }
    func requestNext(completion: @escaping (Result<DecodedPhoto, Error>) -> Void) {
        decodeWorker.async { [self] in
            guard !ticket.isCancelled else { return }
            Resources.shared.change(tasks: 1, id: identifier)
            defer { Resources.shared.change(tasks: -1, id: identifier) }
            let result: Result<DecodedPhoto, Error>
            do {
                var stale = false
                let root = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale).resolvingSymlinksInPath()
                guard !stale else { throw CocoaError(.fileReadNoPermission) }
                let scoped = root.startAccessingSecurityScopedResource()
                if scoped { Resources.shared.change(scopes: 1, id: identifier) }
                defer { if scoped { root.stopAccessingSecurityScopedResource(); Resources.shared.change(scopes: -1, id: identifier) } }
                if queue.needsSnapshot {
                    let snapshot = try PhotoCatalog.scan(root: root, recursive: settings.recursive, cancelled: { ticket.isCancelled })
                    candidateCount = snapshot.count
                    queue.beginRound(snapshot: snapshot, random: settings.random)
                }
                var decoded: DecodedPhoto?
                var refreshedAfterExhaustion = false
                while true {
                    if ticket.isCancelled { throw CatalogError.cancelled }
                    guard let entry = queue.next() else {
                        guard !refreshedAfterExhaustion, candidateCount > 0 else { break }
                        refreshedAfterExhaustion = true
                        let snapshot = try PhotoCatalog.scan(root: root, recursive: settings.recursive, cancelled: { ticket.isCancelled })
                        candidateCount = snapshot.count
                        queue.beginRound(snapshot: snapshot, random: settings.random)
                        continue
                    }
                    do {
                        // Recheck links after snapshot creation; do not intentionally follow substituted links.
                        let info = try entry.url.resourceValues(forKeys: [.isSymbolicLinkKey, .isAliasFileKey, .isRegularFileKey])
                        guard info.isSymbolicLink != true, info.isAliasFile != true, info.isRegularFile == true,
                              entry.url.resolvingSymlinksInPath().standardizedFileURL.path == entry.url.standardizedFileURL.path else { throw CocoaError(.fileReadNoPermission) }
                        decoded = try ImageDecoder.decode(entry.url, viewport: viewport, scale: scale, zoom: settings.maximumZoom)
                        break
                    } catch { queue.reject(entry) }
                }
                guard let decoded else { throw CocoaError(.fileReadCorruptFile) }
                report("session=\(identifier) decoded scope=\(scoped) stale=\(stale) pixels=\(decoded.image.width)x\(decoded.image.height) cachedBytes=\(ImageBudget.shared.current)")
                result = .success(decoded)
            } catch { result = .failure(error) }
            guard !ticket.isCancelled else { return }
            DispatchQueue.main.async { [ticket] in
                guard !ticket.isCancelled else { return }
                completion(result)
            }
        }
    }
    deinit { ticket.cancel() }
}
