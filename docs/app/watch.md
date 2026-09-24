# Watch: recording a demonstration

Watch records one demonstration of a task: a video of the screen and a log of what the person did. Learning (phase 3 of the plan) reads the recording; until then, the review step uses a sample procedure and says so.

## What it records

| | How | Where |
|---|---|---|
| Screen video | ScreenCaptureKit, 10 frames per second, HEVC, longer side at most 1920 px. The person picks a display, window, or app in macOS's own picker, so Understudy never holds blanket Screen Recording access, and macOS shows its recording indicator. | `screen.mov` |
| App switches | `NSWorkspace` activation, with the front window's title | `recording.json` |
| Clicks | A global mouse monitor, plus the Accessibility element under the pointer, walked up to the control a person would name (button, menu item, cell, field): role, title, description, identifier | `recording.json` |
| Typing | Keystrokes grouped into one action per field (after a 1.5 s pause, Return, Tab, an arrow key, a click, or a switch), with the field and its value afterwards | `recording.json` |
| Shortcuts | ⌘ and ⌃ combinations, e.g. `⌘C` | `recording.json` |
| Spreadsheet selections | Selected cells of an Accessibility table in the front window, as `D5=1200 E5=48` | `recording.json` |

Each recording is its own folder in `~/Library/Application Support/Understudy/recordings/<id>/`. `recording.json` (format `Recording` v1 in `UnderstudyCore`) holds the actions on the video's clock, the notes, and the duration. Nothing is uploaded.

**Not recorded:** anything typed into a password field (by role, `AXSecureTextField`; macOS also withholds keystrokes while secure input is on), and anything done inside Understudy itself. The notch strip is excluded from the video.

## Permissions

- **Accessibility**, checked when Watch starts. Without it, Watch doesn't start: the Teach step says why and offers **Open Accessibility Settings**, and macOS shows its own prompt once.
- **Screen**: chosen per recording in macOS's picker. Cancelling the picker cancels Watch.

Builds signed with the fixed identity (`apps/mac/scripts/make-signing-identity.sh`) keep the Accessibility grant across builds; ad-hoc builds lose it every build.

## Using it

1. **Teach a skill** → name and client → **Start Watch**, or press the shortcut (⌥ Space by default) from anywhere.
2. Pick what to record in macOS's picker.
3. Do the task as usual. The notch shows **Watching** with the latest steps; the Teach page lists them with their times. Add notes at any point.
4. Stop with **Stop Watch**, the shortcut, or by clicking the notch. **Record again** starts a new take and keeps the notes; **Review** carries the notes into the review.

## Tests

The capture source is replaceable. `ScriptedCapture` stands in for the screen in the checks and the self-test (it emits the teaching script's five actions and can fail as a missing permission would); `ScreenCapture` is used on a real Mac.

- `WatchChecks`: start failure, actions on Watch's clock, Stop saves the recording and notes, record again, reset, password redaction, the live timer.
- `NotchChecks`: the Watching strip shows the recorded actions in order and says it records on this Mac.
- Self-test: Watch runs with permission turned off and on at random; Watch shows a problem only when idle, and a stopped Watch has saved its actions and notes.

Real capture needs a person at a Mac with the permissions granted, so it is verified by hand; see the checklist in the pull request that introduced it.
