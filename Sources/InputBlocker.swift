import AppKit
import ApplicationServices

/// Swallows every keyboard and mouse event at the session level, before the window
/// server routes it to any application. Key events are handed back to Lockr's own
/// password field, because the tap consumed the copy that would normally be routed.
///
/// A session event tap only works when Lockr is trusted for Accessibility. When it
/// is not, `start()` returns false and the caller must say so loudly: the curtain
/// still appears, but input is *not* blocked.
final class InputBlocker {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Key-down events, already converted for AppKit, for Lockr's own field.
    var onKeyDown: ((NSEvent) -> Void)?

    private static let eventMask: CGEventMask = {
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel,
        ]
        return types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    }()

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let blocker = Unmanaged<InputBlocker>.fromOpaque(refcon).takeUnretainedValue()
                return blocker.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            debugLog("event tap not created: Lockr is not trusted for Accessibility")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.tap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        debugLog("event tap active: keyboard and mouse are consumed at the session level")
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
    }

    /// Returns nil for every event: the whole input stream ends here while locked.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // The system disables taps whose callback stalls; take the stream back at once.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown, let keyEvent = NSEvent(cgEvent: event) {
            onKeyDown?(keyEvent)
        }
        return nil
    }
}

/// Keeps the pointer hidden and immobile for the whole locked session.
///
/// `NSCursor.hide()` is balanced against `unhide` and the cursor reappears as soon
/// as the mouse moves, so it cannot hold. Instead the mouse and the pointer are
/// decoupled (`CGAssociateMouseAndMouseCursorPosition(false)`) and the display
/// cursor is hidden, re-asserted on a timer in case the system shows it again.
final class CursorHider {
    private var timer: Timer?

    func start() {
        _ = CGAssociateMouseAndMouseCursorPosition(0)
        _ = CGDisplayHideCursor(CGMainDisplayID())

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.reassert()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Show-then-hide keeps the display's hide count balanced while forcing the
    /// cursor back out of sight in case anything revealed it.
    private func reassert() {
        _ = CGDisplayShowCursor(CGMainDisplayID())
        _ = CGDisplayHideCursor(CGMainDisplayID())
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        _ = CGDisplayShowCursor(CGMainDisplayID())
        _ = CGAssociateMouseAndMouseCursorPosition(1)
    }
}
