import CoreGraphics

struct PhotoFrame {
    let image: CGImage
    let rect: CGRect
}

enum PhotoRenderer {
    // Both images are normalized opaque decoder outputs. Only the upper image fades.
    static func draw(in context: CGContext, bounds: CGRect, lower: PhotoFrame?, upper: PhotoFrame?, fraction: CGFloat) {
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: bounds)
        context.setAlpha(1)
        context.setBlendMode(.copy)
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(bounds)
        context.setBlendMode(.normal)
        if let lower { context.draw(lower.image, in: lower.rect) }
        if let upper {
            context.setAlpha(min(1, max(0, fraction)))
            context.draw(upper.image, in: upper.rect)
        }
    }
}
