import AppKit
import ScreenSaver

// Ordinary process tests: NEVER count these as real-host G1 passes.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360), styleMask: [.borderless], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
let view = DiagnosticSaverView(frame: NSRect(x: 0, y: 0, width: 640, height: 360), isPreview: true)!
view.startAnimation()
precondition(!view.isAnimating, "detached instance must have no timer")
window.contentView = view
view.startAnimation()
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
precondition(!view.isAnimating, "preview must not keep a timer")
for _ in 0..<20 {
    view.startAnimation()
    view.stopAnimation()
    precondition(!view.isAnimating)
}
view.setFrameSize(.zero)
view.startAnimation()
precondition(!view.isAnimating, "zero size must not animate")
view.removeFromSuperview()
view.stopAnimation()
precondition(view.hasConfigureSheet)
precondition(view.configureSheet != nil)
let proxy = DiagnosticSaverView(frame: NSRect(x: 0, y: 0, width: 640, height: 360), isPreview: false)!
window.contentView = proxy
proxy.startAnimation()
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
precondition(!proxy.isAnimating, "without the system engine, an unflagged proxy must remain static")
proxy.startAnimation()
precondition(!proxy.isAnimating, "repeated starts must not promote the preview")
proxy.stopAnimation()
print("PASS: detached, static preview, 20 ordinary-process stop cycles, zero size, configuration construction")
print("NOT real-host evidence; changed builds require applicable native-host revalidation")
