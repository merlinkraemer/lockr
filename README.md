# Lockr

A minimal, i3lock-style lock screen for macOS that keeps your Mac awake.

The macOS lock screen puts the Mac to sleep and stops what's running.
Lockr puts a black screen over every display, blocks all keyboard and mouse
input, and keeps the system awake. Long builds, downloads and other running
jobs keep going while you're away.

Unlock with **Touch ID** or your **account password**.

- **Cmd-Shift-/** locks from anywhere. No other tools needed
- One small native app, no dependencies, idles in the background with no icon
- Covers every connected display
- Blocks input at the session level, so nothing reaches other apps
- Hides the cursor and suppresses app switching, Force Quit and the Dock
- Touch ID stays armed for the whole session and recovers after sleep or focus loss
- The password is checked against your local account and is never stored or logged
- Optional: stays awake with the lid closed

## Install

```bash
brew install --cask merlinkraemer/tap/lockr
```

Or download `Lockr-<version>.zip` from
[Releases](https://github.com/merlinkraemer/lockr/releases) and move
`Lockr.app` to `/Applications`. Releases are signed and notarized. Lockr needs
macOS 14 or later.

### First run

1. Open Lockr from Spotlight or `/Applications`.
2. macOS asks for **Accessibility** permission. Lockr needs it to block input.
   Enable Lockr under **System Settings → Privacy & Security → Accessibility**.
3. Press **Cmd-Shift-/** to lock. You can [change the shortcut](#custom-shortcut).

From then on Lockr starts in the background at login. macOS lists it under
**System Settings → General → Login Items**.

## Usage

| | |
| --- | --- |
| Lock | **Cmd-Shift-/**, open Lockr again, or run `lockr` |
| Unlock | Touch the Touch ID sensor, or type your password and press Return |
| Stop and turn off at login | `lockr --disable` |
| Turn back on | `lockr --enable` |
| Change the shortcut | `lockr --shortcut ctrl-opt-l` |
| Uninstall | `lockr --disable`, then `brew uninstall --cask lockr` |

### Custom shortcut

```bash
lockr --shortcut                  # show the current one
lockr --shortcut ctrl-opt-l       # set a new one
lockr --shortcut default          # back to cmd-shift-slash
lockr --shortcut none             # turn it off
```

A shortcut is one or more modifiers and one key, joined by `-`. The running
copy picks up the change right away.

- **Modifiers:** `cmd`, `shift`, `opt`, `ctrl`
- **Keys:** `a`–`z`, `0`–`9`, `f1`–`f12`, `slash`, `backslash`, `comma`,
  `period`, `semicolon`, `quote`, `minus`, `equal`, `grave`, `leftbracket`,
  `rightbracket`, `space`, `return`, `tab`, `escape`, `delete`

Pick a shortcut no other app uses. Another app that grabs it first, like a
window manager, keeps Lockr from seeing it.

### Other hotkey tools

`open -a Lockr` also locks. To bind Lockr in another tool (AeroSpace, skhd,
Raycast, Hammerspoon), turn off the built-in shortcut with
`lockr --shortcut none` and bind `open -a Lockr` there:

```toml
# AeroSpace
cmd-shift-slash = 'exec-and-forget open -a Lockr'
```

## Staying awake with the lid closed

While locked, Lockr runs `caffeinate`, which stops idle sleep. Closing the lid
still puts the Mac to sleep, because only `pmset disablesleep` can prevent
that, and it needs root.

To let Lockr do that, allow just those two commands without a password:

```bash
echo "$USER ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 1, /usr/bin/pmset disablesleep 0" | sudo tee /etc/sudoers.d/lockr
sudo chmod 440 /etc/sudoers.d/lockr
```

With that rule, Lockr turns lid-close sleep off when it locks and back on when
it unlocks. Without it, Lockr skips this silently.

To undo it:

```bash
sudo rm /etc/sudoers.d/lockr
```

Things to know:

- A closed laptop in a bag that stays awake gets hot and drains its battery.
  Use this on a desk or on power.
- If Lockr is killed hard (`kill -9`), lid-close sleep stays off until the
  next lock and unlock. You can also turn it back on yourself:
  `sudo pmset disablesleep 0`.

## Customizing

The look is set by constants at the top of
[`Sources/LockSession.swift`](Sources/LockSession.swift): font, sizes, colors
and the password placeholder. If the font isn't installed,
Lockr falls back to the system monospaced font.

## Building from source

Needs the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/merlinkraemer/lockr.git
cd lockr
make install    # builds Lockr.app into ~/Applications
```

The build is ad-hoc signed by default, so macOS treats each rebuild as a new
app and you have to grant Accessibility again. To keep the grant across
rebuilds, sign with your own identity:
`make CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" install`

### Debugging

Lockr logs to stderr. Run the binary directly to see the logs:

```bash
LOCKR_TEST_SECONDS=20 build/Lockr.app/Contents/MacOS/Lockr
```

This locks once and unlocks automatically after the given number of seconds,
so a bug can't lock you out. Note that a binary started from a terminal uses
the terminal's Accessibility permission, not Lockr's.

### Releasing

`scripts/release.sh` builds a universal app, signs it with a Developer ID,
notarizes it and publishes a GitHub release. Run `swift scripts/make-icon.swift`
to redraw the icon.

## Limitations

- Lockr isn't a security boundary like the macOS login window. It stops casual
  access while you're away, not someone with physical access who's determined
  to get in. Someone could hold the power button, for example.
- Displays connected after locking aren't covered.
- After too many failed touches, Touch ID is locked out and you need the password.

## License

[MIT](LICENSE)
