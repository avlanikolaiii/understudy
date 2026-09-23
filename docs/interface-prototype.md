# Understudy: local interface prototype

This is a clickable native Mac app. It is not a working demonstration-learning engine.

## Open

Build from the project root with `app/scripts/bundle.sh`, then open `app/build/Understudy.app`.

The workspace opens at launch. Reopen it from the menu-bar icon with **Open workspace**, or choose **Open your workspace** in the notch panel. The configurable global shortcut (Option-Space by default) opens the notch. The workspace has a Dock entry, standard app menus, a native sidebar and toolbar, and follows the system appearance.

## Try it

1. Choose **Teach a skill** in the toolbar or Home, or press **Command-N**.
2. Enter a task name, client, and notes. Choose **Start Watch demo**.
3. Watch the predefined five-step replay. Add a note, stop or let it finish,
   then choose **Review sample skill**. Review/edit the name, client, and carried
   notes, then save the local sample skill.
4. Choose **Complete sample**, then **Rehearse sample**. Inspect the receipt and expand the report.
5. Choose **Try another case**, select **Missing ad spend**, and rehearse again. Total spend and cost per lead remain missing. The report is an incomplete draft.
6. Optionally export Markdown to a local location you select. The app reads the saved file back and compares its contents with the sample report.

Watch is one shared session across the workspace and notch. Starting from either
surface updates the other. Navigating away, closing the workspace, or opening the
teaching flow again does not restart it. Watch notes copy into sample review without
duplicates. The notch's **Done** dismisses the demo; it does not save a skill.

Open shortcut settings with **Command-comma**, the toolbar gear, the notch gear,
or the menu-bar menu. See `keyboard-shortcuts.md`.

## What really works

- Native workspace navigation and the existing notch/menu-bar entry points.
- Local sample skill creation and saved workflow notes.
- Two deterministic sample scenarios, report previews, and rehearsal history.
- Local Markdown export, with read-back verification at export time.
- Skills and receipts persist in `~/Library/Application Support/Understudy/interface-prototype.json`.

## What is simulated or unverified

- The demonstration is predefined, not recorded.
- The procedure is not learned by AI. Custom workflow notes are stored and shown, not interpreted or enforced.
- Sample figures are fictional. They are not read from Google Sheets or any connected app.
- Receipts describe local sample behavior; they do not verify a client workflow.
- No email, tracker, cloud execution, or background recording is implemented by this interface.
- Existing Supabase sign-in code is retained. Its backend configuration and end-to-end behavior have not been verified in this continuation.

The capture experiment and held-out evaluation data remain separate and unchanged.

## Regression checks

From `app/`, compile the isolated sample domain checks:

```sh
swiftc Sources/Understudy/DemoDomain.swift Tests/PrototypeChecks.swift -o /tmp/understudy-prototype-checks
/tmp/understudy-prototype-checks
```

These check missing-value propagation, simulation disclosure, and serialized receipt preservation. They do not test AI learning.

## Shared Watch checks

```sh
swiftc app/Sources/Understudy/DemoDomain.swift app/Sources/Understudy/WatchSession.swift app/Sources/Understudy/WorkspaceState.swift app/Tests/WorkspaceChecks.swift -o /tmp/understudy-workspace-checks
/tmp/understudy-workspace-checks
```

These check resuming without resetting progress, app navigation, stopping into
review, carrying an unsubmitted note forward, and preventing duplicate notes.

## Verification on 2026-09-23

- Release build with `app/scripts/bundle.sh` passed. Bundle signature and plist
  validation passed. The Command Line Tools linker emitted missing search-path
  warnings, without preventing the build.
- Watch session, shared workspace session, shortcut, and sample-domain checks passed.
- Launched the native workspace. Inspected the sidebar, standard menus, and final
  toolbar actions. Command-N opened teaching; Start Watch demo began the replay;
  entering a note and pressing Return added it to the visible session. Command-comma
  opened shortcut settings.
- Inspected the live light-appearance window and rendered workspace views at normal
  and minimum sizes. Offscreen rendering has artifacts for native selection and
  toolbar materials, so it is not treated as complete visual verification.
- Full app-to-notch interaction, global shortcut activation, dark-mode visual QA,
  and the no-notch fallback remain unverified end to end. UI automation was
  intermittently interrupted by window-state changes and screen-capture errors.
