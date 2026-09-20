import AppKit
import OpenDirectory

/// Checks a typed password against the real local account through OpenDirectory.
/// Nothing is stored or hashed here, and no shell command is involved.
final class PasswordAuthenticator {
    /// The plaintext is only held for the duration of this call. It is never logged,
    /// never written anywhere, and never put into an error message.
    func verify(_ password: String) -> Bool {
        do {
            let node = try ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication))
            let record = try node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
            try record.verifyPassword(password)
            return true
        } catch {
            // OpenDirectory's errors describe the failure, never the password.
            debugLog("password rejected: \(error.localizedDescription)")
            return false
        }
    }
}

/// The small masked field under the `locked` label. Lockr draws it itself instead
/// of using NSTextField so the same view works whether key events arrive through
/// the responder chain or are fed in from the event tap.
final class PasswordFieldView: NSView {
    var onSubmit: ((String) -> Void)?
    /// First keystroke after a submitted attempt; used to dismiss the Touch ID sheet.
    var onUserTyping: (() -> Void)?

    // Plaintext buffer. Kept as UTF-8 bytes so it can be overwritten when cleared.
    private var typed: [UInt8] = []
    private var typedCount = 0

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        NSColor.black.setFill()
        border.fill()
        lockedTextColor.withAlphaComponent(0.25).setStroke()
        border.lineWidth = 1
        border.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let font = NSFont(name: lockedFontFamily, size: passwordFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: passwordFontSize, weight: .light)
        let text: String
        let color: NSColor
        if typedCount == 0 {
            text = passwordPlaceholder
            color = lockedTextColor.withAlphaComponent(0.35)
        } else {
            text = String(repeating: "•", count: typedCount)
            color = lockedTextColor.withAlphaComponent(0.85)
        }
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
        let height = attributed.size().height
        attributed.draw(in: NSRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height))
    }

    override func keyDown(with event: NSEvent) {
        // Anything else (Escape, function keys, symbols) is simply dropped.
        switch event.keyCode {
        case 36, 76:
            submit()
        case 51: // delete
            guard typedCount > 0 else { return }
            typedCount -= 1
            typed.removeLast()
            needsDisplay = true
        default:
            // Command/control combinations are not text; paste is deliberately ignored
            // so the clipboard can never feed the field.
            guard !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control) else { return }
            guard let characters = event.characters, !characters.isEmpty else { return }
            guard characters.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) else { return }
            typed.append(contentsOf: characters.utf8)
            typedCount += 1
            needsDisplay = true
            onUserTyping?()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    /// Wrong password: empty the field, shake it briefly, stay locked.
    func rejectPassword() {
        clearBuffer()
        needsDisplay = true

        let animation = CAKeyframeAnimation(keyPath: "position.x")
        let center = layer?.position.x ?? frame.midX
        animation.values = [0, -shakeDistance, shakeDistance, -shakeDistance / 2, 0].map { center + $0 }
        animation.duration = shakeDuration
        layer?.add(animation, forKey: "shake")
    }

    private func submit() {
        let password = String(decoding: typed, as: UTF8.self)
        clearBuffer()
        needsDisplay = true
        onSubmit?(password)
    }

    /// Plaintext handling: overwrite the bytes before dropping the buffer, and keep
    /// the value out of logs, errors and disk. The copy handed to the caller lives
    /// only for the duration of the password check.
    private func clearBuffer() {
        for index in typed.indices { typed[index] = 0 }
        typed.removeAll(keepingCapacity: false)
        typedCount = 0
    }
}
