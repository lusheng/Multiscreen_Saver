import AppKit
import ScreenSaver
import os

let moduleID = "com.lusheng.MultiscreenSaver"
let diagnosticLog = Logger(subsystem: moduleID, category: "G1")

// Only synthetic labels, dimensions and counters go into public log messages.
func report(_ message: String) {
    diagnosticLog.notice("\(message, privacy: .public)")
}

final class WorkTicket {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

// Per-process counters: never infer total host resources from these counters alone.
final class Resources {
    static let shared = Resources()
    private let lock = NSLock()
    private var tasks = 0
    private var scopes = 0
    func change(tasks t: Int = 0, scopes s: Int = 0, id: String) {
        lock.lock(); tasks += t; scopes += s
        let message = "id=\(id) resources tasks=\(tasks) scopes=\(scopes)"
        lock.unlock(); report(message)
    }
}

func moduleDefaults() -> ScreenSaverDefaults? {
    ScreenSaverDefaults(forModuleWithName: moduleID)
}
