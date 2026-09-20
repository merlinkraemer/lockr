# Lockr

A minimal macOS lock curtain: launch it and every display is covered by an opaque
black window with the word `locked` and a small masked password field underneath.

While locked:

- **Input does not reach other applications.** A `CGEventTap` at
  `.cgSessionEventTap` / `.headInsertEventTap` consumes every keyboard, mouse and
  scroll event. The consumed key events are fed straight into Lockr's own password
  field. This needs the app to be trusted for **Accessibility**; without that
  permission the curtain still appears, but it warns loudly (stderr and on the
  curtain) that input is *not* blocked. Lockr never grants the permission itself.
- **The cursor is hidden and cannot be moved**: the pointer is decoupled with
  `CGAssociateMouseAndMouseCursorPosition(0)`, the display cursor is hidden and
  re-asserted on a timer. Both are restored on every exit path.
- `NSApp.presentationOptions` adds
  `[.disableProcessSwitching, .disableForceQuit, .disableSessionTermination, .disableHideApplication, .hideDock, .hideMenuBar]`
  as a second, Accessibility-independent layer against Cmd-Tab, Cmd-Opt-Esc, etc.
- `caffeinate -dis` runs as a child, so the display and system stay awake.

Unlocking always kills the child and quits:

- Touch ID is attempted **once**, at lock time, with
  `.deviceOwnerAuthenticationWithBiometrics` (biometrics only, so macOS never pops
  its own password sheet over Lockr's UI). A cancelled or failed attempt leaves the
  curtain up.
- Otherwise type the password of the local account and press Enter. It is verified
  through OpenDirectory (`ODNode(session:type:.authenticationSearchPath)` ->
  `record(withRecordType:kODRecordTypeUsers, name:NSUserName())` ->
  `verifyPassword`). Nothing is stored, hashed or shelled out to. A wrong password
  clears the field with a brief shake and lets the user retry; `verifyPassword` can
  trigger the account's failed-attempt policy, so Lockr never retries on its own.
- The typed plaintext is kept as a byte buffer that is overwritten when cleared; it
  is never logged, never written to disk and never put in an error message.

## Build

Needs Xcode command line tools and an Apple Development signing identity
(the identity is set at the top of the `Makefile`):

```sh
make            # -> build/Lockr.app
make install    # -> ~/Applications/Lockr.app (no sudo)
make clean
```

## Accessibility permission

System Settings > Privacy & Security > **Accessibility** > enable **Lockr**.

Grant it to the copy you actually launch (`~/Applications/Lockr.app`). Without it
Lockr logs

```
[lockr] WARNING: Lockr is not trusted for Accessibility, keystrokes and clicks are NOT blocked.
```

and shows `accessibility permission missing - input not blocked` on the curtain.
The app is signed with a fixed Apple Development identity, but rebuilding can still
make macOS ask again.

## Use

```sh
open -a Lockr      # lock now; unlocking quits the process
```

Lockr is not resident: no menu bar item, no Dock icon (`LSUIElement`), no login
item, no hotkey of its own, no config file. In AeroSpace the binding is
`cmd-shift-slash`.

Every `NSScreen` present at launch gets a borderless window at
`CGShieldingWindowLevel()`, and Lockr re-activates itself if focus is stolen.
Multi-display hotplug is **not** handled: screens plugged in after launch are not
covered. Launching Lockr twice does not stack a second curtain - the second
instance sees the first one and exits.

## Safety valve for testing

```sh
LOCKR_TEST_SECONDS=5 open -a Lockr
```

If `LOCKR_TEST_SECONDS` is set to a number, the app unlocks and quits after that
many seconds, unconditionally. Use it for every scripted run - never launch Lockr
for a test without it. Under the valve the Touch ID prompt is skipped, so a test
run can only end through the timer or a password.

## This is not a security boundary

Lockr is a curtain, not a lock screen replacement. It does not protect against
anything that does not go through the GUI:

- SSH / a remote shell can kill the process, and so does a reboot or a crash.
- A crash (or `kill -9`) also orphans the `caffeinate` child; `pkill caffeinate`
  clean up if that ever happens.
- `Cmd+Ctrl+Q` and the hardware lock key still work, and closing the lid sleeps
  the machine as usual.

The password is checked by the system's OpenDirectory record, so it is only as
strong as the account password.
