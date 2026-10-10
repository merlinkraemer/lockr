import AppKit

/// Minimal trace output, visible when the binary is started from a shell.
func debugLog(_ message: String) {
    FileHandle.standardError.write(Data("[lockr] \(message)\n".utf8))
}

let usage = """
usage: lockr [--enable | --disable | --help]

  (no option)  lock now
  --enable     start Lockr at login (the default)
  --disable    stop Lockr and don't start it at login

Cmd-Shift-/ locks while Lockr runs in the background.
"""

let arguments = Array(CommandLine.arguments.dropFirst())
let testSeconds = ProcessInfo.processInfo.environment["LOCKR_TEST_SECONDS"].flatMap(Double.init)

func otherInstances() -> [NSRunningApplication] {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .filter { $0.processIdentifier != getpid() }
}

switch arguments.first {
case "--help", "-h":
    print(usage)
    exit(0)
case "--enable":
    do {
        try LoginAgent.enable()
        print("Lockr starts at login. Cmd-Shift-/ locks.")
        exit(0)
    } catch {
        print("could not enable: \(error.localizedDescription)")
        exit(1)
    }
case "--disable":
    do { try LoginAgent.disable() } catch { debugLog("unregister: \(error.localizedDescription)") }
    for app in otherInstances() { app.terminate() }
    print("Lockr stopped and won't start at login. `lockr --enable` turns it back on.")
    exit(0)
case "--background", nil:
    break
default:
    print(usage)
    exit(2)
}

let launchedInBackground = arguments.first == "--background"

// From a shell (not a debug run): hand over to Launch Services, which either
// starts Lockr or tells the running copy to lock. Apps it launches have launchd
// as their parent.
if !launchedInBackground, testSeconds == nil, getppid() != 1 {
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-b", bundleIdentifier]
    try open.run()
    open.waitUntilExit()
    exit(open.terminationStatus)
}

// One copy only: a second one would stack a second curtain and hotkey.
if let running = otherInstances().first {
    debugLog("already running as pid \(running.processIdentifier), exiting")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
delegate.launchedInBackground = launchedInBackground
delegate.quitAfterUnlock = testSeconds != nil
app.delegate = delegate
// No Dock icon and no menu bar; also declared via LSUIElement in Info.plist.
app.setActivationPolicy(.accessory)

// MANDATORY safety valve: LOCKR_TEST_SECONDS=N locks once, auto-unlocks after N
// seconds and quits, unconditionally. Touch ID stays armed for the whole window,
// so the biometrics path is exercised exactly as in a real lock.
if let seconds = testSeconds, seconds > 0 {
    debugLog("LOCKR_TEST_SECONDS=\(seconds): auto-unlock armed")
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        debugLog("LOCKR_TEST_SECONDS elapsed, unlocking")
        delegate.unlock()
        NSApp.terminate(nil)
    }
}

// Unlock cleanly on SIGTERM/SIGINT, taking the caffeinate child with us.
var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGTERM, SIGINT] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        delegate.unlock()
        NSApp.terminate(nil)
    }
    source.resume()
    signalSources.append(source)
}

app.run()
