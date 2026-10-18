import Foundation
import CoreGraphics

struct KenBurnsPath {
    let base: CGSize
    let viewport: CGSize
    let startOffset: CGPoint
    let endOffset: CGPoint
    let endZoom: CGFloat
    init(image: CGSize, viewport: CGSize, backingScale: CGFloat, maximumZoom: Double, generator: inout SeededGenerator) {
        self.viewport = viewport
        let margin = 2 / max(1, backingScale)
        let scale = max((viewport.width + 2 * margin) / max(1, image.width), (viewport.height + 2 * margin) / max(1, image.height))
        let fitted = CGSize(width: image.width * scale, height: image.height * scale)
        base = fitted
        endZoom = CGFloat(Double.random(in: 1.1...maximumZoom, using: &generator))
        func offset(_ zoom: CGFloat, _ rng: inout SeededGenerator) -> CGPoint {
            let x = max(0, (fitted.width * zoom - viewport.width) / 2 - margin)
            let y = max(0, (fitted.height * zoom - viewport.height) / 2 - margin)
            return CGPoint(x: CGFloat.random(in: -x...x, using: &rng), y: CGFloat.random(in: -y...y, using: &rng))
        }
        startOffset = offset(1, &generator)
        endOffset = offset(endZoom, &generator)
    }
    func rect(progress: Double) -> CGRect {
        let t = CGFloat(min(1, max(0, progress)))
        let z = 1 + (endZoom - 1) * t
        let x = startOffset.x + (endOffset.x - startOffset.x) * t
        let y = startOffset.y + (endOffset.y - startOffset.y) * t
        return CGRect(x: (viewport.width - base.width * z) / 2 + x,
                      y: (viewport.height - base.height * z) / 2 + y,
                      width: base.width * z, height: base.height * z)
    }
}

struct PlaybackTiming {
    let finishIncoming: Bool
    let startNext: Bool
    static func evaluate(now: Double, currentStart: Double?, incomingStart: Double?, ready: Bool, duration: Double, fade: Double) -> PlaybackTiming {
        let finish = incomingStart.map { now - $0 >= fade } ?? false
        let activeStart = finish ? incomingStart : currentStart
        let canStart = (incomingStart == nil || finish) && ready && (activeStart.map { now - $0 >= duration } ?? false)
        return PlaybackTiming(finishIncoming: finish, startNext: canStart)
    }
}
