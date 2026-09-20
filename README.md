# Lockr

A minimal full-screen lock curtain for macOS: black screen, the word `locked`, a masked
password field. Unlock by typing your account password, or with the Touch ID prompt that
appears once at lock time. Passwords are checked against the local account with
OpenDirectory; nothing is stored. While locked, Lockr keeps the display and the system
awake.

## Build

Needs the Xcode command line tools.

```sh
make            # -> build/Lockr.app (ad-hoc signed)
make install    # -> ~/Applications/Lockr.app (no sudo)
make clean
```

Lockr is ad-hoc signed by default. macOS ties the Accessibility grant to the code
signature, so a rebuild is a new signature and the permission must be granted again. Sign
with a stable identity to avoid that:

```sh
make CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" install
```

## Accessibility permission

Lockr blocks keystrokes and clicks with a session-level event tap, so it must be enabled
under **System Settings > Privacy & Security > Accessibility**. Without it input is *not*
blocked: the curtain appears but warns on screen that the permission is missing, and
keystrokes still reach other applications. Lockr cannot grant this itself.

## Lock

```sh
open -a Lockr
```

Bind it to a hotkey with whatever tool you use. In AeroSpace:

```
cmd-shift-slash = 'exec-and-forget open -a Lockr'
```

Unlocking quits the process. Lockr is not resident: no menu bar item, no Dock icon
(`LSUIElement`), no login item, no config file; a second launch exits instead of stacking
another curtain.

## Development

`LOCKR_TEST_SECONDS=N` makes Lockr unlock and quit after N seconds, unconditionally, and
skips the Touch ID prompt. Use it for every scripted run; never launch Lockr without it.

```sh
LOCKR_TEST_SECONDS=5 open -a Lockr
```

Font family, label size and colour are constants at the top of `Sources/AppDelegate.swift`.

## Limitations

This is a curtain, not a security boundary. SSH or any other shell can kill the process,
and so can a reboot; there is no crash watchdog, so if Lockr dies the curtains go with it.
Killing Lockr orphans its `caffeinate` child (`pkill caffeinate` cleans up). Only the
screens present at launch are covered - plugging in a display does not add a curtain.
`Cmd+Ctrl+Q` and the hardware lock key still work, and closing the lid sleeps the machine.
