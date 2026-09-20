import Foundation

/// Keeps the display and the system awake for as long as the curtain is up.
final class Caffeine {
    private var process: Process?

    var pid: Int32? { process?.processIdentifier }

    func start() {
        guard process == nil else { return }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        child.arguments = ["-dis"]
        do {
            try child.run()
            process = child
        } catch {
            debugLog("could not start caffeinate: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard let child = process else { return }
        process = nil
        child.terminate()
        child.waitUntilExit()
    }
}
