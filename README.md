# Lockr

> Minimal i3-style lock screen for macOS.
> Keeps the Mac awake while locked.

Unlock with your account password or Touch ID.

## Install

```bash
make install
```

## Lock

```bash
open -a Lockr
```

Bind that command to any macOS shortcut tool you use, e.g. AeroSpace, Karabiner-Elements, Shortcuts, Raycast, Hammerspoon, etc.

### AeroSpace

```toml
cmd-shift-slash = 'exec-and-forget open -a Lockr'
```

## Requires

Enable **System Settings → Privacy & Security → Accessibility** so Lockr can block keyboard and mouse input.
