import AppKit

// Font family taken verbatim from Ghostty's `font-family` setting.
private let lockedFontFamily = "Cousine Nerd Font Mono"
// Point size for the `locked` label.
private let lockedFontSize: CGFloat = 24
// `locked` label colour: the terminal's effective foreground, gruvbox-tinted white #ebdbb2.
private let lockedTextColor = NSColor(srgbRed: 0xEB / 255, green: 0xDB / 255, blue: 0xB2 / 255, alpha: 1)

/// Escape hatches are only suppressed while Lockr is frontmost, which it stays.
private let lockedPresentationOptions: NSApplication.PresentationOptions = [
    .disableProcessSwitching,
    .disableForceQuit,
    .disableSessionTermination,
    .disableHideApplication,
    .hideDock,
    .hideMenuBar,
]

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [CurtainWindow] = []
    private let authenticator = Authenticator()
    private let caffeine = Caffeine()
    private var authInProgress = false
    private let testSeconds: Double?

    init(testSeconds: Double?) {
        self.testSeconds = testSeconds
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Multi-display hotplug is not handled: cover the screens present at launch.
        for screen in NSScreen.screens {
            let window = CurtainWindow(screen: screen)
            window.onInteraction = { [weak self] in self?.requestAuthentication() }
            windows.append(window)
        }

        caffeine.start()
        showCurtains()
        debugLog("locked \(windows.count) display(s), caffeinate pid \(caffeine.pid.map(String.init) ?? "none")")
    }

    /// Any keypress or click asks the system to authenticate the device owner.
    func requestAuthentication() {
        guard testSeconds == nil else {
            debugLog("LOCKR_TEST_SECONDS is set, ignoring interaction")
            return
        }
        guard !authInProgress else { return }
        authInProgress = true
        authenticator.authenticate(reason: "Unlock Lockr") { [weak self] success in
            guard let self else { return }
            self.authInProgress = false
            if success {
                debugLog("authenticated, unlocking")
                self.shutDown()
            } else {
                debugLog("authentication cancelled or failed, staying locked")
                self.showCurtains()
            }
        }
    }

    /// The single teardown path: debug timeout, signal and successful auth all use it.
    func shutDown() {
        NSApp.presentationOptions = []
        caffeine.stop()
        NSApp.terminate(nil)
    }

    private func showCurtains() {
        for window in windows { window.makeKeyAndOrderFront(nil) }
        NSApp.activate()
        NSApp.presentationOptions = lockedPresentationOptions
    }
}

/// One opaque shield per screen, above every other window level.
private final class CurtainWindow: NSWindow {
    var onInteraction: (() -> Void)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        setFrame(screen.frame, display: true)

        let curtain = CurtainView(frame: CGRect(origin: .zero, size: screen.frame.size))
        curtain.onInteraction = { [weak self] in self?.onInteraction?() }
        contentView = curtain
        makeFirstResponder(curtain)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        onInteraction?()
    }
}

/// Black surface with the word `locked` in the middle; eats every click and key.
private final class CurtainView: NSView {
    var onInteraction: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = NSAttributedString(string: "locked", attributes: [
            .font: NSFont(name: lockedFontFamily, size: lockedFontSize)
                ?? NSFont.monospacedSystemFont(ofSize: lockedFontSize, weight: .light),
            .foregroundColor: lockedTextColor,
            .paragraphStyle: paragraph,
        ])
        let height = text.size().height
        text.draw(in: NSRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height))
    }

    override func keyDown(with event: NSEvent) { onInteraction?() }
    override func mouseDown(with event: NSEvent) { onInteraction?() }
    override func rightMouseDown(with event: NSEvent) { onInteraction?() }
    override func otherMouseDown(with event: NSEvent) { onInteraction?() }
}
