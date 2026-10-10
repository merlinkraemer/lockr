import AppKit
import ApplicationServices

// Font family for the `locked` label and the password field; falls back to the
// system monospaced font when it is not installed.
let lockedFontFamily = "Cousine Nerd Font Mono"
// Point size for the `locked` label.
let lockedFontSize: CGFloat = 18
// `locked` label colour: gruvbox-tinted white #ebdbb2.
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
let blockingWarning = "input not blocked - check Accessibility permission"
let warningFontSize: CGFloat = 11
let warningColor = NSColor(srgbRed: 0.85, green: 0.35, blue: 0.35, alpha: 1)
// Dim hint under the password field when Touch ID cannot be used.
let hintFontSize: CGFloat = 11
let hintColor = lockedTextColor.withAlphaComponent(0.4)

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
    private var focusWatchdog: Timer?
    private var foreignFocusTicks = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Without Accessibility input cannot be blocked, and the system's permission
        // dialog would sit hidden behind the curtain. Ask, then quit without locking.
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        guard AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) else {
            debugLog("not trusted for Accessibility: asked for permission, not locking")
            NSApp.terminate(nil)
            return
        }
        let blockingInput = inputBlocker.start()

        // Multi-display hotplug is not handled: cover the screens present at launch.
        for screen in NSScreen.screens {
            let window = CurtainWindow(screen: screen, showBlockingWarning: !blockingInput)
            window.onSubmitPassword = { [weak self] password in self?.verifyPassword(password) }
            windows.append(window)
        }

        // Touch ID is armed for the whole locked session and re-armed after every
        // non-fatal outcome; password typing stays the fallback and never blocks it.
        authenticator.onUnlock = { [weak self] in
            debugLog("Touch ID succeeded, unlocking")
            self?.shutDown()
        }
        authenticator.onStatus = { [weak self] status in
            switch status {
            case .lockedOut:
                self?.showBiometricHint("touch id locked - use password")
            case .unavailable:
                self?.showBiometricHint("touch id unavailable - use password")
            case .armed, .retrying:
                break
            }
        }
        // The panel is gone now, so the curtain can take the focus back before the
        // next attempt is armed.
        authenticator.onEvaluationEnded = { [weak self] in
            self?.showCurtains()
        }

        caffeine.start()
        cursorHider.start()
        // Arm Touch ID only once the curtain owns the focus: the system panel takes the
        // focus for the whole evaluation and must be allowed to win it (see
        // `activateIfNeeded`).
        showCurtains { [weak self] in
            self?.authenticator.start(reason: "Unlock Lockr")
        }

        if blockingInput {
            inputBlocker.onKeyDown = { [weak self] event in
                guard let self else { return }
                // The system panel owns the focus while biometrics is armed; taking it
                // back would cancel the Touch ID match (see `activateIfNeeded`). Typing
                // still reaches the password field either way.
                if !self.biometricsOwnFocus,
                   NSWorkspace.shared.frontmostApplication?.processIdentifier != getpid() {
                    debugLog("focus lost while locked, re-activating")
                    self.showCurtains()
                }
                self.windows.first?.handleKeyDown(event)
            }
        } else {
            // Never fail open silently: the curtain is up but input reaches other apps.
            debugLog("WARNING: event tap failed, keystrokes and clicks are NOT blocked.")
        }

        watchBiometricFocus()

        // Focus must stay on the curtain; take it back if anything steals it, unless
        // the authentication panel holds it (see `activateIfNeeded`).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isShuttingDown, !self.biometricsOwnFocus else { return }
            debugLog("focus lost while locked, re-activating")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, !self.isShuttingDown, !self.biometricsOwnFocus else { return }
                self.showCurtains()
            }
        }
    }

    /// The single teardown path: debug timeout, signal, Touch ID and password all use it.
    /// Cursor and event tap are always restored here, whatever the exit reason.
    func shutDown() {
        isShuttingDown = true
        focusWatchdog?.invalidate()
        authenticator.stop()
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

    /// A pending evaluation dies silently once its panel loses the focus (see
    /// `activateIfNeeded`), so restart it whenever that may have happened: another
    /// app holds the focus for a couple of seconds, or the Mac comes back from
    /// sleep or the system lock screen.
    private func watchBiometricFocus() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.authenticator.isEvaluating else {
                self?.foreignFocusTicks = 0
                return
            }
            let frontmost = NSWorkspace.shared.frontmostApplication
            let foreign = frontmost?.processIdentifier != getpid() && !self.authPanelIsFrontmost
            self.foreignFocusTicks = foreign ? self.foreignFocusTicks + 1 : 0
            if self.foreignFocusTicks >= 2 {
                debugLog("focus held by \(frontmost?.bundleIdentifier ?? "?") during Touch ID")
                self.foreignFocusTicks = 0
                self.authenticator.restart()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        focusWatchdog = timer

        let restartAfterWake: (Notification) -> Void = { [weak self] note in
            debugLog("\(note.name.rawValue), restarting Touch ID")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self?.authenticator.restart()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: restartAfterWake)
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: restartAfterWake)
    }

    private func showBiometricHint(_ text: String) {
        for window in windows { window.setBiometricHint(text) }
    }

    private func showCurtains(completion: (() -> Void)? = nil) {
        for window in windows { window.makeKeyAndOrderFront(nil) }
        NSApp.activate()
        NSApp.presentationOptions = lockedPresentationOptions
        activateIfNeeded(attempts: 5, completion: completion)
    }

    /// macOS may refuse an activation request (cooperative activation), so retry a
    /// few times until the curtain really is frontmost and its window is key.
    ///
    /// Never while LocalAuthentication's panel is up: the panel belongs to another
    /// process (`coreautha`) and holds the focus for the whole evaluation. Taking it
    /// back makes the panel report "UI lost focus" (LAError -4), after which
    /// LocalAuthentication stops the Touch ID match operation while the evaluation
    /// stays pending - a sensor touch then does nothing at all.
    private func activateIfNeeded(attempts: Int, completion: (() -> Void)? = nil) {
        guard !isShuttingDown else { return }
        guard !biometricsOwnFocus else {
            completion?()
            return
        }
        guard attempts > 0, NSWorkspace.shared.frontmostApplication?.processIdentifier != getpid() else {
            completion?()
            return
        }
        NSApp.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.activateIfNeeded(attempts: attempts - 1, completion: completion)
        }
    }

    /// True while a biometric evaluation is pending or its panel is already frontmost:
    /// the panel owns the focus and Lockr must not take it back.
    private var biometricsOwnFocus: Bool {
        authenticator.isEvaluating || authPanelIsFrontmost
    }

    /// `coreautha` (`com.apple.LocalAuthentication.UIAgent`) draws that panel.
    private var authPanelIsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.LocalAuthentication.UIAgent"
    }
}

/// One opaque shield per screen, above every other window level.
private final class CurtainWindow: NSWindow {
    var onSubmitPassword: ((String) -> Void)? {
        get { curtain.onSubmitPassword }
        set { curtain.onSubmitPassword = newValue }
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

    func setBiometricHint(_ text: String) {
        curtain.biometricHint = text
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
    /// Short dim line under the field when Touch ID cannot be used. Redrawn in place.
    var biometricHint: String? {
        didSet { needsDisplay = true }
    }

    private let showBlockingWarning: Bool

    init(frame: NSRect, showBlockingWarning: Bool) {
        self.showBlockingWarning = showBlockingWarning
        super.init(frame: frame)
        passwordField.onSubmit = { [weak self] password in self?.onSubmitPassword?(password) }
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

        // Optional dim lines sit under the password field, warning first.
        var footerY = (bounds.height - groupHeight) / 2 - passwordFieldGap
        if showBlockingWarning {
            let warningFont = NSFont(name: lockedFontFamily, size: warningFontSize)
                ?? NSFont.monospacedSystemFont(ofSize: warningFontSize, weight: .light)
            let warning = NSAttributedString(string: blockingWarning, attributes: [
                .font: warningFont,
                .foregroundColor: warningColor,
                .paragraphStyle: paragraph,
            ])
            footerY -= warning.size().height
            warning.draw(in: NSRect(x: 0, y: footerY, width: bounds.width, height: warning.size().height))
        }
        if let biometricHint {
            let hintFont = NSFont(name: lockedFontFamily, size: hintFontSize)
                ?? NSFont.monospacedSystemFont(ofSize: hintFontSize, weight: .light)
            let hint = NSAttributedString(string: biometricHint, attributes: [
                .font: hintFont,
                .foregroundColor: hintColor,
                .paragraphStyle: paragraph,
            ])
            footerY -= hint.size().height + passwordFieldGap / 2
            hint.draw(in: NSRect(x: 0, y: footerY, width: bounds.width, height: hint.size().height))
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(passwordField)
    }

    func rejectPassword() {
        passwordField.rejectPassword()
    }
}
