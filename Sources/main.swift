import AppKit

/// Minimal trace output, visible when the binary is started from a shell.
func debugLog(_ message: String) {
    FileHandle.standardError.write(Data("[lockr] \(message)\n".utf8))
}

// Singleton guard: a second launch must not stack a second curtain.
let otherInstances = NSRunningApplication
    .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.merlinkraemer.lockr")
    .filter { $0.processIdentifier != getpid() }
if !otherInstances.isEmpty {
    debugLog("already locked by pid \(otherInstances[0].processIdentifier), exiting")
    exit(0)
}

let testSeconds = ProcessInfo.processInfo.environment["LOCKR_TEST_SECONDS"].flatMap(Double.init)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// No Dock icon and no menu bar; also declared via LSUIElement in Info.plist.
app.setActivationPolicy(.accessory)

// MANDATORY safety valve: LOCKR_TEST_SECONDS=N auto-unlocks and quits after N seconds,
// unconditionally. Touch ID stays armed for the whole window, so the biometrics path
// is exercised exactly as in a real lock.
if let seconds = testSeconds, seconds > 0 {
    debugLog("LOCKR_TEST_SECONDS=\(seconds): auto-unlock armed")
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        debugLog("LOCKR_TEST_SECONDS elapsed, unlocking")
        delegate.shutDown()
    }
}

// Take the caffeinate child with us on SIGTERM/SIGINT instead of orphaning it.
var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGTERM, SIGINT] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler { delegate.shutDown() }
    source.resume()
    signalSources.append(source)
}

app.run()
