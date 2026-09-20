# Lockr

A minimal macOS lock curtain: launch it and every display is covered by an opaque
black window with the word `locked` in the middle. Any keypress or mouse click asks
the system to authenticate the device owner (`LAContext.evaluatePolicy(.deviceOwnerAuthentication)`),
which gives Touch ID and the system's own password fallback. Lockr never sees or
validates a password itself.

While locked, Lockr keeps `caffeinate -dis` running as a child process, so the
display and the system stay awake behind the curtain (e.g. while watching a build,
a download or a long-running agent). On unlock it kills the child and quits.

## Build

Needs Xcode command line tools and an Apple Development signing identity
(the identity is set at the top of the `Makefile`):

```sh
make            # -> build/Lockr.app
make install    # -> ~/Applications/Lockr.app (no sudo)
make clean
```

## Use

```sh
open -a Lockr      # lock now; unlocking quits the process
```

Lockr is not resident: no menu bar item, no Dock icon (`LSUIElement`), no login
item, no hotkey of its own, no config file. In AeroSpace the binding is
`cmd-shift-slash`.

Lockr sets `NSApp.presentationOptions` to
`[.disableProcessSwitching, .disableForceQuit, .disableSessionTermination, .disableHideApplication, .hideDock, .hideMenuBar]`
and stays frontmost, and every `NSScreen` present at launch gets a borderless
window at `CGShieldingWindowLevel()`. Multi-display hotplug is **not** handled:
screens plugged in after launch are not covered.

Launching Lockr twice does not stack a second curtain - the second instance sees
the first one and exits.

## Safety valve for testing

```sh
LOCKR_TEST_SECONDS=5 open -a Lockr
```

If `LOCKR_TEST_SECONDS` is set to a number, the app unlocks and quits after that
many seconds, unconditionally, and the curtain ignores keypresses and clicks so
the timed unlock always wins. Use it for every scripted run - never launch Lockr
for a test without it.

## This is not a security boundary

Lockr is a curtain, not a lock screen replacement. It does not protect against
anything that does not go through the GUI:

- SSH / a remote shell can kill the process, and so does a reboot or a crash.
- A crash (or `kill -9`) also orphans the `caffeinate` child; `pkill caffeinate`
  clean up if that ever happens.
- `Cmd+Ctrl+Q` and the hardware lock key still work, and closing the lid sleeps
  the machine as usual.

The authentication itself is the system's, so it is only as strong as Touch ID
or the account password.
