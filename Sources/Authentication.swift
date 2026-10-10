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
/// `CGShieldingWindowLevel()`, so it stays hidden behind the curtain. Hidden is fine,
/// but unfocused is not: the Touch ID match only runs while that panel keeps the
/// focus. Re-activating Lockr while an evaluation is pending makes the panel report
/// "UI lost focus" (LAError -4), and LocalAuthentication stops the match operation
/// while the evaluation stays pending - the sensor then answers to nothing. Callers
/// must therefore leave the focus alone for as long as `isEvaluating` is true.
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

    /// Called on the main thread once an evaluation has ended and its panel is gone,
    /// so the caller may safely take the focus back.
    var onEvaluationEnded: (() -> Void)?

    /// True from just before an evaluation is handed to LocalAuthentication until its
    /// outcome arrives (or `stop()` runs): the system panel owns the focus meanwhile.
    private(set) var isEvaluating = false

    private var context: LAContext?
    private var attempt = 0
    private var running = false
    private var reason = ""

    /// Arms Touch ID and keeps re-arming after non-fatal outcomes.
    func start(reason: String) {
        running = true
        self.reason = reason
        arm()
    }

    /// Abandons a pending evaluation and arms a fresh one. For when the panel has
    /// lost the focus to someone else (another app, sleep, the system lock screen):
    /// such an evaluation stays pending with the sensor dead and never ends itself.
    func restart() {
        guard running, isEvaluating else { return }
        debugLog("biometrics #\(attempt): restarting stuck evaluation")
        attempt += 1
        isEvaluating = false
        context?.invalidate()
        context = nil
        onEvaluationEnded?()
        scheduleRearm()
    }

    /// Ends the current evaluation; used when the lockdown itself is ending.
    func stop() {
        running = false
        isEvaluating = false
        attempt += 1
        context?.invalidate()
        context = nil
    }

    private func arm() {
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

        debugLog("biometrics #\(attempt): armed")
        isEvaluating = true
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running, self.attempt == attempt else { return }
                self.isEvaluating = false
                self.context = nil
                if success {
                    debugLog("biometrics #\(attempt): success")
                    self.onUnlock?()
                    return
                }
                let status = Self.status(for: error as NSError?)
                debugLog("biometrics #\(attempt): ended (\(Self.describe(error as NSError?))) -> \(status)")
                self.onEvaluationEnded?()
                self.onStatus?(status)
                switch status {
                case .lockedOut, .unavailable:
                    return
                case .armed, .retrying:
                    // The context is spent; re-arm so a later touch still unlocks.
                    self.scheduleRearm()
                }
            }
        }
    }

    /// A small delay keeps a burst of instant errors from spinning, and lets the
    /// caller take the focus back before the next panel claims it.
    private func scheduleRearm() {
        let attempt = self.attempt
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.running, self.attempt == attempt, !self.isEvaluating else { return }
            self.arm()
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
}
