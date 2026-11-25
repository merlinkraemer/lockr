# Lockr state

## Touch ID dead after a reboot (2026-11-24/25)

Symptom: after the Mac restarted (~13:30 WITA, 24 Nov) the sensor was ignored on
the Lockr curtain; only the password unlocked. No hint was shown.

Findings:
- The login agent copy (pid 766, started 13:34 at login) handled one lock at
  14:37-14:41. Its single `evaluatePolicy` (cid 6) stayed pending the whole 4
  minutes and was never restarted; the password unlock invalidated it (LA -9).
- A fresh copy (test lock via `LOCKR_TEST_SECONDS`, then the restarted agent with
  the real hotkey) unlocked by Touch ID first try. So the stuck state belonged to
  the agent started right after the reboot, not to grants or enrolment
  (`bioutil -r`: unlock biometrics on; Accessibility grant fine, input blocked).
- Baseline while a working evaluation waits: `com.apple.LocalAuthentication.UIAgent`
  (coreautha) is frontmost the whole time.
- Gap: the 1 s focus watchdog counted only other apps as foreign. A panel that lost
  the focus to Lockr itself, or never got it, kept a dead evaluation forever.
- Not proven: why the post-reboot agent's panel lost or never got the focus. The
  unified log kept no info-level LocalAuthentication lines from that lock, and
  `debugLog` only wrote to stderr, which the agent discards.

Fix (branch `fix/touchid-stuck-after-reboot`):
- Watchdog restarts the evaluation when anyone but the panel holds the focus for 3 s.
- `debugLog` also writes to the unified log:
  `log show --predicate 'subsystem == "com.merlinkraemer.lockr"' --last 1h`.

Verified: fix build (Developer ID signed, Accessibility grant carried over) unlocks
by Touch ID in a test lock; trace lines appear in the unified log. The post-reboot
case itself is not reproduced; next reboot, check the log above if it recurs.

Workaround without the fix: restart the agent
(`launchctl kickstart -k gui/$(id -u)/com.merlinkraemer.lockr.agent`).

Test harness on the Mac: `~/lockr-debug/run-test.sh <app> <seconds> <tag>` runs a
test lock as a GUI-session launchd job with stderr in `~/lockr-debug/`, booting the
agent out and re-enabling it afterwards. `~/lockr-debug/src` is a worktree of the
branch. Signing over ssh fails (locked keychain); `~/lockr-debug/sign.plist` signs
inside the GUI session instead.
