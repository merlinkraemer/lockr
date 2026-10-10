import Foundation

/// Keeps the display and the system awake for as long as the curtain is up.
///
/// `caffeinate` cannot stop the sleep that closing the lid triggers. Only
/// `pmset disablesleep` can, and it needs root, so Lockr tries it through
/// `sudo -n` (never prompts) and simply skips it when no sudoers rule allows it.
final class Caffeine {
    private var process: Process?
    private var lidSleepDisabled = false

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

        lidSleepDisabled = Self.setDisableSleep(true)
        debugLog(lidSleepDisabled
            ? "lid-close sleep disabled"
            : "lid-close sleep still active (no sudoers rule for pmset disablesleep)")
    }

    func stop() {
        if lidSleepDisabled, Self.setDisableSleep(false) {
            lidSleepDisabled = false
        }
        guard let child = process else { return }
        process = nil
        child.terminate()
        child.waitUntilExit()
    }

    private static func setDisableSleep(_ disabled: Bool) -> Bool {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        child.arguments = ["-n", "/usr/bin/pmset", "disablesleep", disabled ? "1" : "0"]
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        do {
            try child.run()
            child.waitUntilExit()
            return child.terminationStatus == 0
        } catch {
            return false
        }
    }
}
