import AppKit
import ServiceManagement

let bundleIdentifier = "com.merlinkraemer.lockr"

/// Lockr stays running in the background, invisible, and locks on the hotkey or
/// whenever it is opened again (`open -a Lockr`, Spotlight, Finder).
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Started by the login agent: wait for the hotkey instead of locking now.
    var launchedInBackground = false
    /// Debug runs lock once and quit afterwards.
    var quitAfterUnlock = false

    private var hotkey: Hotkey?
    private var session: LockSession?

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotkey = Hotkey { [weak self] in self?.lock() }
        if !quitAfterUnlock { LoginAgent.registerUnlessOptedOut() }
        if !launchedInBackground { lock() }
    }

    /// A background copy that is told to quit (a Homebrew upgrade, Activity Monitor)
    /// exits non-zero, so the login agent starts the current version again. Once
    /// `--disable` has unregistered the agent, nothing restarts it.
    func applicationWillTerminate(_ notification: Notification) {
        if launchedInBackground { exit(1) }
    }

    /// `open -a Lockr` on the running app lands here.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        lock()
        return false
    }

    func lock() {
        guard session == nil else { return }
        let session = LockSession()
        session.onEnd = { [weak self] in
            self?.session = nil
            if self?.quitAfterUnlock == true { NSApp.terminate(nil) }
        }
        guard session.start() else {
            if quitAfterUnlock { NSApp.terminate(nil) }
            return
        }
        self.session = session
    }

    /// Unlocks if locked; used by the debug timeout and on SIGTERM/SIGINT.
    func unlock() {
        session?.end()
    }
}

/// Starts Lockr in the background at login, through a launch agent shipped inside
/// the bundle (Contents/Library/LaunchAgents).
enum LoginAgent {
    private static let service = SMAppService.agent(plistName: "\(bundleIdentifier).agent.plist")
    private static let optOutKey = "LoginAgentDisabled"

    static func registerUnlessOptedOut() {
        guard !optedOut, service.status != .enabled else { return }
        do {
            try service.register()
            debugLog("login agent registered")
        } catch {
            debugLog("could not register login agent: \(error.localizedDescription)")
        }
    }

    static func enable() throws {
        optedOut = false
        try service.register()
    }

    static func disable() throws {
        optedOut = true
        try service.unregister()
    }

    /// Stored under the bundle ID explicitly: the `lockr` command is a symlink to
    /// the binary, and run that way the standard defaults land in a "lockr" domain.
    private static var optedOut: Bool {
        get {
            CFPreferencesGetAppBooleanValue(optOutKey as CFString, bundleIdentifier as CFString, nil)
        }
        set {
            CFPreferencesSetAppValue(optOutKey as CFString, newValue as CFBoolean, bundleIdentifier as CFString)
            CFPreferencesAppSynchronize(bundleIdentifier as CFString)
        }
    }
}
