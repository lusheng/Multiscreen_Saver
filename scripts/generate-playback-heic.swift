import Foundation
import ImageIO
for route in ["H", "V"] {
 let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("LocalPhotos/Playback/\(route)")
 let src = CGImageSourceCreateWithURL(root.appendingPathComponent("01-\(route).jpg") as CFURL,nil)!
 let image=CGImageSourceCreateImageAtIndex(src,0,nil)!
 let dest=CGImageDestinationCreateWithURL(root.appendingPathComponent("08-\(route).heic") as CFURL,"public.heic" as CFString,1,nil)!
 CGImageDestinationAddImage(dest,image,nil)
 precondition(CGImageDestinationFinalize(dest))
}
