import LocalAuthentication

/// Thin wrapper over LAContext: Touch ID with the system's own password fallback.
/// Lockr never sees or validates a password itself.
final class Authenticator {
    func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            debugLog("deviceOwnerAuthentication unavailable: \(error?.localizedDescription ?? "unknown error")")
            completion(false)
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
            if let error {
                debugLog("authentication returned error: \(error.localizedDescription)")
            }
            DispatchQueue.main.async { completion(success) }
        }
    }
}
