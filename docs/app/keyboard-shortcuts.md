# Keyboard shortcut

Open **Keyboard Shortcut…** from Understudy's menu-bar menu, or use the gear in
the notch panel. Click **Record shortcut**, then press a key with Command,
Option, or Control. The change is saved automatically on this Mac.

- Default: **Option-Space**. **Restore default** switches back.
- Escape, Cancel recording, closing the window, or switching to another app
  cancels recording without changing the binding.
- The shortcut opens or closes the notch. During simulated Watch, it stops the
  replay and opens its result. Recording the current binding cancels recording
  instead of triggering that action.
- Invalid combinations, common app commands, enabled macOS symbolic shortcuts,
  and conflicting Carbon registrations are rejected. Failed remaps retain the
  previous working binding and saved preference.
- Some apps intercept keys without registering a Carbon hotkey. Those conflicts
  cannot be detected reliably. If another app responds, choose another combination.
- The binding uses a physical key code; its label comes from the keyboard layout
  at recording time. Re-record after a layout change to update the displayed label.

The setting is stored in app-local UserDefaults under `globalShortcut.v1`.
The recorder only listens inside the focused settings window. Global activation
uses Carbon registration; no Accessibility or screen-recording permission is added.

## Checks

```sh
swiftc apps/mac/Sources/Understudy/KeyboardShortcut.swift apps/mac/Tests/ShortcutChecks.swift -o /tmp/understudy-shortcut-checks
/tmp/understudy-shortcut-checks
apps/mac/scripts/bundle.sh
```

Checks cover persistence, invalid keys, cancellation, restore, failed startup,
failed remapping, retaining the old registration until its replacement succeeds,
layout-label changes, event conversion, and real Carbon conflict/release behavior.

## Verification on 2026-09-23

- Shortcut checks passed, including real Carbon duplicate-registration rejection
  and successful reuse after releasing a registration.
- Opened the native settings window using Command-comma and inspected its saved
  shortcut and recorder controls. The recorder entered its listening state in the
  isolated UI check.
- Complete keystroke remapping and global notch activation were not verified end
  to end through UI automation. Window-state changes and capture errors interrupted
  those checks; the underlying registration and preference behavior passed tests.
