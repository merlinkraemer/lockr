#!/bin/bash
# Renders the real curtain view to docs/screenshot.png without locking anything.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Expose the file-private view to the snapshot entry point.
sed 's/^private final class CurtainView/final class CurtainView/' Sources/LockSession.swift > "$tmp/LockSession.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import AppKit
func debugLog(_ message: String) {}
let bundleIdentifier = "com.merlinkraemer.lockr"
let size = CGSize(width: 1200, height: 560)
let view = CurtainView(frame: CGRect(origin: .zero, size: size), showBlockingWarning: false)
view.layoutSubtreeIfNeeded()
let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
view.cacheDisplay(in: view.bounds, to: rep)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT
swiftc -swift-version 5 -o "$tmp/snapshot" "$tmp/main.swift" "$tmp/LockSession.swift" \
  Sources/Authentication.swift Sources/Caffeine.swift Sources/InputBlocker.swift Sources/PasswordAuth.swift
"$tmp/snapshot" docs/screenshot.png
echo "wrote docs/screenshot.png"
