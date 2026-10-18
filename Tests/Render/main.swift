import Foundation
import CoreGraphics

let space = CGColorSpace(name: CGColorSpace.sRGB)!
func bitmap(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
}
func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGImage {
    let c = bitmap(4, 4);c.setFillColor(CGColor(colorSpace: space, components: [r,g,b,1])!)
    c.fill(CGRect(x: 0,y: 0,width: 4,height: 4));return c.makeImage()!
}
let red = solid(1,0,0), blue = solid(0,0,1), black = solid(0,0,0)
var rng = SeededGenerator(seed: 611)
var checkedPixels = 0
for viewport in [CGSize(width: 96,height: 54), CGSize(width: 54,height: 96)] {
    let bounds = CGRect(origin: .zero,size: viewport)
    let ctx = bitmap(Int(viewport.width), Int(viewport.height))
    for _ in 0..<100 {
        let a = KenBurnsPath(image: CGSize(width: Int.random(in: 1...10000,using: &rng),height: Int.random(in: 1...10000,using: &rng)), viewport: viewport, backingScale: 2, maximumZoom: 1.2, generator: &rng)
        let b = KenBurnsPath(image: CGSize(width: Int.random(in: 1...10000,using: &rng),height: Int.random(in: 1...10000,using: &rng)), viewport: viewport, backingScale: 2, maximumZoom: 1.2, generator: &rng)
        for fraction in [0.0,0.01,0.25,0.5,0.75,0.99,1] {
            // Reuse the backing store and deliberately dirty it between frames.
            ctx.setFillColor(CGColor(gray: 1,alpha: 1));ctx.fill(CGRect(x: 10,y: 10,width: 20,height: 20))
            PhotoRenderer.draw(in: ctx,bounds: bounds,lower: PhotoFrame(image: red,rect: a.rect(progress: 0.7 + 0.3*fraction)),
                               upper: PhotoFrame(image: blue,rect: b.rect(progress: 0.3*fraction)),fraction: fraction)
            let bytes=ctx.data!.assumingMemoryBound(to: UInt8.self)
            for i in stride(from: 0,to: ctx.bytesPerRow*ctx.height,by: 4) {
                precondition(bytes[i+3]==255,"transparent output")
                precondition(bytes[i+1]==0,"background/old marker exposed")
                precondition(abs(Int(bytes[i])-Int((255*(1-fraction)).rounded()))<=2,"red fade mismatch/dark flash")
                precondition(abs(Int(bytes[i+2])-Int((255*fraction).rounded()))<=2,"blue fade mismatch")
                checkedPixels += 1
            }
        }
    }
    PhotoRenderer.draw(in: ctx,bounds: bounds,lower: PhotoFrame(image: black,rect: bounds),upper: nil,fraction: 0)
    let bytes=ctx.data!.assumingMemoryBound(to: UInt8.self)
    precondition(bytes[0]==0 && bytes[3]==255,"black photo content must remain valid opaque content")
}
print("PASS: \(checkedPixels) composited pixels, opaque red/blue overlap, no dark flash or stale marks, black-photo content preserved")
