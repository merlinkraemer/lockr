import AppKit
import LocalAuthentication

/// Biometric unlock, armed for the whole locked session.
///
/// Every attempt gets a fresh `LAContext`, because a context is single-use once an
/// evaluation ends and an attempt can end without unlocking for many reasons (a
/// missed touch, a system cancel). Each ending either unlocks the session or
/// re-arms, so a sensor touch works at any point while locked - including after
/// typing, deleting, or waiting a minute. Only a biometric lockout (too many
/// failed touches) or missing/unenrolled hardware stops the re-arming, and both
/// fall back to the password field.
///
/// Deliberately biometrics only: `.deviceOwnerAuthentication` would let macOS pop
/// its own password sheet over Lockr's curtain, which would fight the typed-password
/// field. The system panel that LocalAuthentication draws for a biometrics
/// evaluation lives at window level 1000, far below the curtain's
/// `CGShieldingWindowLevel()`, so it stays hidden behind the curtain. That is
/// intentional and harmless: the sensor itself is armed either way, and a touch
/// unlocks without a visible dialog to fight the curtain.
final class Authenticator {
    enum Status {
        /// An evaluation is pending or a fresh one was just armed.
        case armed
        /// The attempt ended without unlocking and a new one has been armed.
        case retrying
        /// Too many failed touches: biometrics is off until the session ends.
        case lockedOut
        /// No enrolled biometry or no hardware: password only.
        case unavailable
    }

    var onUnlock: (() -> Void)?
    var onStatus: ((Status) -> Void)?

    private var context: LAContext?
    private var attempt = 0
    private var running = false

    /// Arms Touch ID and keeps re-arming after non-fatal outcomes.
    func start(reason: String) {
        running = true
        arm(reason: reason)
    }

    /// Ends the current evaluation; used when the lockdown itself is ending.
    func stop() {
        running = false
        attempt += 1
        context?.invalidate()
        context = nil
    }

    private func arm(reason: String) {
        guard running else { return }
        attempt += 1
        let attempt = self.attempt
        let context = LAContext()
        self.context = context

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            debugLog("biometrics: unavailable before attempt (\(Self.describe(error))); password only")
            self.context = nil
            onStatus?(.unavailable)
            return
        }

        debugLog("biometrics #\(attempt): armed (biometryType=\(context.biometryType.rawValue))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.running, self.attempt == attempt else { return }
            Self.logAuthPanel(attempt: attempt)
        }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running, self.attempt == attempt else { return }
                self.context = nil
                if success {
                    debugLog("biometrics #\(attempt): success")
                    self.onUnlock?()
                    return
                }
                let status = Self.status(for: error as NSError?)
                debugLog("biometrics #\(attempt): ended (\(Self.describe(error as NSError?))) -> \(status)")
                self.onStatus?(status)
                switch status {
                case .lockedOut, .unavailable:
                    return
                case .armed, .retrying:
                    // The context is spent; re-arm so a later touch still unlocks.
                    // A small delay keeps a burst of instant errors from spinning.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self, self.running, self.attempt == attempt else { return }
                        self.arm(reason: reason)
                    }
                }
            }
        }
    }

    private static func status(for error: NSError?) -> Status {
        guard let error, error.domain == LAErrorDomain else { return .retrying }
        switch error.code {
        case LAError.biometryLockout.rawValue:
            return .lockedOut
        case LAError.biometryNotAvailable.rawValue,
             LAError.biometryNotEnrolled.rawValue,
             LAError.passcodeNotSet.rawValue:
            return .unavailable
        default:
            return .retrying
        }
    }

    private static func describe(_ error: NSError?) -> String {
        guard let error else { return "nil" }
        return "\(error.domain)#\(error.code): \(error.localizedDescription)"
    }

    /// Reports any LocalAuthentication panel window and its level. The panel is
    /// drawn at level 1000, below the curtain's `CGShieldingWindowLevel()`, so this
    /// proves remotely that the sensor is armed while the panel stays hidden.
    private static func logAuthPanel(attempt: Int) {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            debugLog("biometrics #\(attempt): panel check unavailable")
            return
        }
        let mine = Int(getpid())
        let panels: [String] = list.compactMap { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int, pid != mine else { return nil }
            let owner = window[kCGWindowOwnerName as String] as? String ?? "?"
            let level = window[kCGWindowLayer as String] as? Int ?? -999
            let name = window[kCGWindowName as String] as? String ?? ""
            let low = (owner + " " + name).lowercased()
            guard low.contains("coreauth") || low.contains("biometr") || low.contains("auth") else { return nil }
            return "\(owner) level=\(level) name=\"\(name)\""
        }
        let curtainLevel = Int(CGShieldingWindowLevel())
        if panels.isEmpty {
            debugLog("biometrics #\(attempt): no auth panel window; curtain level=\(curtainLevel)")
        } else {
            debugLog("biometrics #\(attempt): auth panel [\(panels.joined(separator: "; "))]; curtain level=\(curtainLevel)")
        }
    }
}
