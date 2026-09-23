# Watch in the notch: simulated

This slice replays five predefined steps based on the Phase A teaching script in
`docs/capture-experiment.md`. It does not read capture logs, record the screen,
learn a skill, access connected apps, or read evaluation data. The timer and
interaction are real; the displayed workflow is simulated.

## Try it

1. Run `app/scripts/bundle.sh`, then open `app/build/Understudy.app`.
2. Press your configured shortcut (Option-Space by default), click the notch, or choose **Open Understudy** from the menu bar.
3. Choose **Watch a new task**, labeled **Simulated**. No account setup is needed.
4. Watch the pulsing dot, elapsed timer, and five steps advance every five seconds.
5. Enter a rule and press Return or **Add**. Blank rules are ignored. Notes stay in
   memory for this session and are not interpreted or saved as a skill.
6. Choose **Stop** partway through. The timer freezes; only finished steps have
   checkmarks. Any unsubmitted rule is retained. **Replay** restarts the clock
   while keeping rules; **Done** returns to the panel home.
7. Let a replay finish: at 25 seconds it says **Replay complete**. It does not
   claim to have learned a skill or start the next slice.

The configured shortcut stops an active replay and shows its partial result. Clicking the
collapsed notch during playback does the same. This follows the original
teaching interaction described in the Claude conversation.

Collapsing the panel with Escape, the close control, or clicking away leaves the
replay running. The menu-bar **Open Understudy** item reopens it for inspection.
The collapsed notch dot pulses during playback. Reduced Motion uses a steady dot. A new Watch session
after **Done**, or quitting the app, clears these temporary notes.

Change the shortcut through the notch gear or the menu-bar **Keyboard Shortcut…** item. See `docs/keyboard-shortcuts.md`.

## Check the session behavior

From the repository root:

```sh
swiftc app/Sources/Understudy/WatchSession.swift app/Tests/WatchChecks.swift -o /tmp/understudy-watch-checks
/tmp/understudy-watch-checks
```

This checks timer progression and cancellation, exact step boundaries, Stop,
automatic completion, blank/trimmed rules, pending-rule retention, replay, and
fresh-session reset. Visual and keyboard checks still require opening the app.

## Verification on 2026-09-23

- Release bundle built with `app/scripts/bundle.sh`; bundle signature and plist checks passed.
- Session checks passed, including the live timer and cancellation after Stop.
- Rendered the actual Watch view at 420 points wide in playing, stopped, and
  completed states. Inspected labels, progress, rules, and controls; corrected
  primary-button contrast for an inactive panel.
- The rebuilt app launched. Full notch interaction, the global shortcut,
  Reduced Motion, and the no-notch fallback were not verified end to end.
  Native UI inspection was interrupted by window-state changes.
