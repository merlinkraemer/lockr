# Lockr

A minimal, i3lock-style lock screen for macOS that keeps your Mac awake.

The macOS lock screen puts the Mac to sleep and stops what's running.
Lockr puts a black screen over every display, blocks all keyboard and mouse
input, and keeps the system awake. Long builds, downloads and other running
jobs keep going while you're away.

Unlock with **Touch ID** or your **account password**.

- One small native binary, no dependencies, ~800 lines of Swift
- Covers every connected display
- Blocks input at the session level, so nothing reaches other apps
- Hides the cursor and suppresses app switching, Force Quit and the Dock
- Touch ID stays armed for the whole session and recovers after sleep or focus loss
- The password is checked against your local account and is never stored or logged
- Optional: stays awake with the lid closed

## Requirements

- macOS 14 or later
- Xcode Command Line Tools (`xcode-select --install`)

## Install

### Homebrew

```bash
brew install merlinkraemer/tap/lockr
```

This builds Lockr on your Mac and adds a `lockr` command. Each `brew upgrade`
rebuilds the app, so macOS asks for Accessibility again.

### From source

```bash
git clone https://github.com/merlinkraemer/lockr.git
cd lockr
make install
```

This builds `Lockr.app` and copies it to `~/Applications`.

The first time you run it, Lockr asks for **Accessibility** permission, which it
needs to block input, and quits without locking. Enable Lockr under
**System Settings → Privacy & Security → Accessibility**, then run it again.

> The build is ad-hoc signed by default, so macOS treats each rebuild as a new
> app and you have to re-grant Accessibility. To keep the grant across rebuilds,
> sign with your own identity:
> `make CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" install`

## Usage

```bash
lockr            # Homebrew
open -a Lockr    # from source
```

Bind that to a hotkey with whatever tool you use: AeroSpace, skhd, Hammerspoon,
Raycast, Karabiner-Elements or Shortcuts.

**AeroSpace**

```toml
cmd-shift-slash = 'exec-and-forget open -a Lockr'
```

**skhd**

```
cmd + shift - 0x2C : open -a Lockr
```

To unlock, touch the Touch ID sensor, or type your password and press Return.

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
[`Sources/AppDelegate.swift`](Sources/AppDelegate.swift): font, sizes, colors
and the password placeholder. If the font isn't installed, Lockr falls back to
the system monospaced font. Rebuild with `make install` after you change them.

## Debugging

Lockr logs to stderr. Run the binary directly to see the logs:

```bash
LOCKR_TEST_SECONDS=20 ~/Applications/Lockr.app/Contents/MacOS/Lockr
```

`LOCKR_TEST_SECONDS` unlocks automatically after the given number of seconds.
Use it when you try changes, so a bug can't lock you out. `Ctrl-C` in that
terminal won't reach it while input is blocked, but `kill` from an SSH session
will (Lockr unlocks cleanly on SIGTERM).

## Limitations

- Lockr isn't a security boundary like the macOS login window. It stops casual
  access while you're away, not someone with physical access who's determined
  to get in. Someone could hold the power button, for example.
- Displays connected after locking aren't covered.
- After too many failed touches, Touch ID is locked out and you need the password.

## License

[MIT](LICENSE)
