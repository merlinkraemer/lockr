import Carbon.HIToolbox

/// The lock shortcut, written like `cmd-shift-slash` or `ctrl-opt-l`.
struct Shortcut {
    static let defaultSpec = "cmd-shift-slash"
    static let changedNotification = Notification.Name("\(bundleIdentifier).shortcutChanged")

    let keyCode: UInt32
    let modifiers: UInt32

    private static let modifierNames: [String: Int] = [
        "cmd": cmdKey, "command": cmdKey,
        "shift": shiftKey,
        "opt": optionKey, "option": optionKey, "alt": optionKey,
        "ctrl": controlKey, "control": controlKey,
    ]

    private static let keyNames: [String: Int] = {
        var keys: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
            "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
            "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
            "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
            "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "slash": kVK_ANSI_Slash, "backslash": kVK_ANSI_Backslash, "comma": kVK_ANSI_Comma,
            "period": kVK_ANSI_Period, "semicolon": kVK_ANSI_Semicolon, "quote": kVK_ANSI_Quote,
            "minus": kVK_ANSI_Minus, "equal": kVK_ANSI_Equal, "grave": kVK_ANSI_Grave,
            "leftbracket": kVK_ANSI_LeftBracket, "rightbracket": kVK_ANSI_RightBracket,
            "space": kVK_Space, "return": kVK_Return, "tab": kVK_Tab, "escape": kVK_Escape,
            "delete": kVK_Delete,
        ]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
                            kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        for (index, code) in functionKeys.enumerated() { keys["f\(index + 1)"] = code }
        return keys
    }()

    /// One key plus at least one modifier, so typing can never trigger a lock.
    init?(_ spec: String) {
        let parts = spec.lowercased().split(separator: "-").map(String.init)
        guard let key = parts.last, let code = Self.keyNames[key], parts.count >= 2 else { return nil }
        var modifiers = 0
        for name in parts.dropLast() {
            guard let flag = Self.modifierNames[name] else { return nil }
            modifiers |= flag
        }
        keyCode = UInt32(code)
        self.modifiers = UInt32(modifiers)
    }

    static let help = """
    A shortcut is modifiers and one key joined by "-", e.g. cmd-shift-slash or ctrl-opt-l.
      modifiers: cmd, shift, opt, ctrl
      keys:      a-z, 0-9, f1-f12, slash, backslash, comma, period, semicolon, quote,
                 minus, equal, grave, leftbracket, rightbracket, space, return, tab,
                 escape, delete
    """

    /// The saved shortcut text: a spec, "none", or the default.
    static var stored: String {
        get { Preferences.string("Shortcut") ?? defaultSpec }
        set { Preferences.set("Shortcut", newValue == defaultSpec ? nil : newValue as CFString) }
    }
}

/// Lockr's settings, always under the bundle ID: the `lockr` command is a symlink
/// to the binary, and run that way the standard defaults land in a "lockr" domain.
enum Preferences {
    static func string(_ key: String) -> String? {
        CFPreferencesCopyAppValue(key as CFString, bundleIdentifier as CFString) as? String
    }

    static func bool(_ key: String) -> Bool {
        CFPreferencesGetAppBooleanValue(key as CFString, bundleIdentifier as CFString, nil)
    }

    static func set(_ key: String, _ value: CFPropertyList?) {
        CFPreferencesSetAppValue(key as CFString, value, bundleIdentifier as CFString)
        CFPreferencesAppSynchronize(bundleIdentifier as CFString)
    }
}
