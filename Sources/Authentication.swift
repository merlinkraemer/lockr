import LocalAuthentication

/// Thin wrapper over LAContext for a single Touch ID attempt at lock time.
///
/// Deliberately biometrics only: `.deviceOwnerAuthentication` would let macOS pop
/// its own password sheet over Lockr's curtain, which would fight the typed-password
/// field. A cancelled or failed attempt simply leaves the curtain up.
final class Authenticator {
    private var context: LAContext?

    func authenticateWithBiometrics(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        self.context = context

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            debugLog("biometrics unavailable: \(error.map { String(describing: $0.code) } ?? "unknown error")")
            self.context = nil
            completion(false)
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            DispatchQueue.main.async { [weak self] in
                self?.context = nil
                if let error {
                    debugLog("biometric attempt ended: \((error as NSError).code)")
                }
                completion(success)
            }
        }
    }

    /// Typing wins over the system sheet: drop a pending Touch ID prompt as soon as
    /// the user starts entering a password instead.
    func cancelPendingBiometrics() {
        context?.invalidate()
        context = nil
    }
}
