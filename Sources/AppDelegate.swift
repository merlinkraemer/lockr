import AppKit
import ApplicationServices

// Font family taken verbatim from Ghostty's `font-family` setting.
let lockedFontFamily = "Cousine Nerd Font Mono"
// Point size for the `locked` label.
let lockedFontSize: CGFloat = 18
// `locked` label colour: the terminal's effective foreground, gruvbox-tinted white #ebdbb2.
let lockedTextColor = NSColor(srgbRed: 0xEB / 255, green: 0xDB / 255, blue: 0xB2 / 255, alpha: 1)
// Password field: same family, smaller and quieter than the label.
let passwordFontSize: CGFloat = 13
let passwordFieldSize = CGSize(width: 180, height: 24)
let passwordFieldGap: CGFloat = 14
let passwordPlaceholder = "password"
// Wrong-password shake.
let shakeDistance: CGFloat = 6
let shakeDuration: CFTimeInterval = 0.3
// Shown on the curtain when input cannot actually be blocked.
let blockingWarning = "accessibility permission missing - input not blocked"
let warningFontSize: CGFloat = 11
let warningColor = NSColor(srgbRed: 0.85, green: 0.35, blue: 0.35, alpha: 1)

/// Escape hatches are only suppressed while Lockr is frontmost, which it stays.
let lockedPresentationOptions: NSApplication.PresentationOptions = [
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
    private let inputBlocker = InputBlocker()
    private let cursorHider = CursorHider()
    private let passwordAuthenticator = PasswordAuthenticator()
    private var authInProgress = false
    private var isShuttingDown = false
    private let testSeconds: Double?

    init(testSeconds: Double?) {
        self.testSeconds = testSeconds
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Multi-display hotplug is not handled: cover the screens present at launch.
        let trustedForAccessibility = AXIsProcessTrusted()
        for screen in NSScreen.screens {
            let window = CurtainWindow(screen: screen, showBlockingWarning: !trustedForAccessibility)
            window.onSubmitPassword = { [weak self] password in self?.verifyPassword(password) }
            window.onUserTyping = { [weak self] in self?.authenticator.cancelPendingBiometrics() }
            windows.append(window)
        }

        caffeine.start()
        cursorHider.start()
        showCurtains()

        if trustedForAccessibility, inputBlocker.start() {
            inputBlocker.onKeyDown = { [weak self] event in
                guard let self else { return }
                if NSWorkspace.shared.frontmostApplication?.processIdentifier != getpid() {
                    debugLog("focus lost while locked, re-activating")
                    self.showCurtains()
                }
                self.windows.first?.handleKeyDown(event)
            }
        } else {
            // Never fail open silently: the curtain is up but input reaches other apps.
            debugLog("WARNING: Lockr is not trusted for Accessibility, keystrokes and clicks are NOT blocked.")
            debugLog("WARNING: enable Lockr under System Settings > Privacy & Security > Accessibility.")
        }

        // Touch ID is attempted once, at lock time; password typing is the fallback.
        if testSeconds == nil {
            authenticator.authenticateWithBiometrics(reason: "Unlock Lockr") { [weak self] success in
                guard let self else { return }
                if success {
                    debugLog("Touch ID succeeded, unlocking")
                    self.shutDown()
                } else {
                    debugLog("Touch ID cancelled or failed, staying locked (type your password)")
                }
            }
        }

        // Focus must stay on the curtain; take it back if anything steals it.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isShuttingDown else { return }
            debugLog("focus lost while locked, re-activating")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, !self.isShuttingDown else { return }
                self.showCurtains()
            }
        }
    }

    /// The single teardown path: debug timeout, signal, Touch ID and password all use it.
    /// Cursor and event tap are always restored here, whatever the exit reason.
    func shutDown() {
        isShuttingDown = true
        debugLog("unlocking, restoring input and cursor")
        inputBlocker.stop()
        cursorHider.stop()
        NSApp.presentationOptions = []
        caffeine.stop()
        NSApp.terminate(nil)
    }

    /// The plaintext arrives from the field's cleared buffer and only lives inside
    /// this call: it is never logged, never written to disk, never echoed.
    private func verifyPassword(_ password: String) {
        guard !authInProgress else { return }
        authInProgress = true
        // Off the main thread so the event tap callback never stalls.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let accepted = self.passwordAuthenticator.verify(password)
            DispatchQueue.main.async {
                self.authInProgress = false
                if accepted {
                    debugLog("password accepted, unlocking")
                    self.shutDown()
                } else {
                    debugLog("password rejected, staying locked")
                    for window in self.windows { window.rejectPassword() }
                }
            }
        }
    }

    private func showCurtains() {
        for window in windows { window.makeKeyAndOrderFront(nil) }
        NSApp.activate()
        NSApp.presentationOptions = lockedPresentationOptions
        activateIfNeeded(attempts: 5)
    }

    /// macOS may refuse an activation request (cooperative activation), so retry a
    /// few times until the curtain really is frontmost and its window is key.
    private func activateIfNeeded(attempts: Int) {
        guard attempts > 0, !isShuttingDown else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != getpid() else { return }
        NSApp.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.activateIfNeeded(attempts: attempts - 1)
        }
    }
}

/// One opaque shield per screen, above every other window level.
private final class CurtainWindow: NSWindow {
    var onSubmitPassword: ((String) -> Void)? {
        get { curtain.onSubmitPassword }
        set { curtain.onSubmitPassword = newValue }
    }
    var onUserTyping: (() -> Void)? {
        get { curtain.onUserTyping }
        set { curtain.onUserTyping = newValue }
    }

    private let curtain: CurtainView

    init(screen: NSScreen, showBlockingWarning: Bool) {
        curtain = CurtainView(frame: CGRect(origin: .zero, size: screen.frame.size),
                              showBlockingWarning: showBlockingWarning)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        setFrame(screen.frame, display: true)

        contentView = curtain
        makeFirstResponder(curtain.passwordField)
    }

    func rejectPassword() {
        curtain.rejectPassword()
    }

    func handleKeyDown(_ event: NSEvent) {
        curtain.passwordField.keyDown(with: event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Black surface with the word `locked` and a password field under it.
private final class CurtainView: NSView {
    let passwordField = PasswordFieldView()
    var onSubmitPassword: ((String) -> Void)?
    var onUserTyping: (() -> Void)?

    private let showBlockingWarning: Bool

    init(frame: NSRect, showBlockingWarning: Bool) {
        self.showBlockingWarning = showBlockingWarning
        super.init(frame: frame)
        passwordField.onSubmit = { [weak self] password in self?.onSubmitPassword?(password) }
        passwordField.onUserTyping = { [weak self] in self?.onUserTyping?() }
        addSubview(passwordField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Lockr has no nib")
    }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        passwordField.frame = CGRect(
            x: (bounds.width - passwordFieldSize.width) / 2,
            y: (bounds.height - passwordFieldSize.height) / 2 - passwordFieldSize.height / 2 - passwordFieldGap / 2,
            width: passwordFieldSize.width,
            height: passwordFieldSize.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let labelFont = NSFont(name: lockedFontFamily, size: lockedFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: lockedFontSize, weight: .light)
        let label = NSAttributedString(string: "locked", attributes: [
            .font: labelFont,
            .foregroundColor: lockedTextColor,
            .paragraphStyle: paragraph,
        ])
        let labelHeight = label.size().height
        // The label sits just above the password field, both centred as a group.
        let groupHeight = labelHeight + passwordFieldGap + passwordFieldSize.height
        label.draw(in: NSRect(
            x: 0,
            y: (bounds.height + groupHeight) / 2 - labelHeight,
            width: bounds.width,
            height: labelHeight
        ))

        guard showBlockingWarning else { return }
        let warningFont = NSFont(name: lockedFontFamily, size: warningFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: warningFontSize, weight: .light)
        let warning = NSAttributedString(string: blockingWarning, attributes: [
            .font: warningFont,
            .foregroundColor: warningColor,
            .paragraphStyle: paragraph,
        ])
        warning.draw(in: NSRect(
            x: 0,
            y: (bounds.height - groupHeight) / 2 - passwordFieldGap - warning.size().height,
            width: bounds.width,
            height: warning.size().height
        ))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(passwordField)
    }

    func rejectPassword() {
        passwordField.rejectPassword()
    }
}
