# Understudy: the app prototype

This is a clickable native Mac app. It is not a working demonstration-learning engine.

## One app, two surfaces (since 2026-09-23 evening)

- **Main window** is the home: Home, Teach a skill, Skills, Receipts, and Account (sign-in).
- **The notch** is the live companion, styled and animated like the landing page's hero demo. The pill has a glowing dot. It springs open into a strip with a label, a timer, and the last 4 steps: Watching (pulsing dot), New skill, Rehearsing (blue dot, read-only), and Receipt. It never asks for sign-in or typing.
- **One data layer** (`SkillLibrary`): before sign-in it runs in **Sample mode**, saved on this Mac in the same JSON file as before, so old data carries over. After sign-in, skills and receipts come from the Supabase account. Receipts need `supabase/migrations/0002_receipt_details.sql`.
- The shortcut (default Option-Space) follows the page's story: press it once to start Watch, and press it again to stop and open the review.
- `open apps/mac/build/Understudy.app --args --notch-demo` plays the landing page's full sequence in the real notch, labeled "Concept demonstration".

## Open

Build from the project root with `apps/mac/scripts/bundle.sh`, then open `apps/mac/build/Understudy.app`.

The main window opens at launch. Reopen it from the menu-bar icon with **Open Understudy**, or click the notch. The configurable global shortcut (Option-Space by default) starts or stops Watch. The workspace has a Dock entry, standard app menus, a native sidebar and toolbar, and follows the system appearance.

## Try it

1. Choose **Teach a skill** in the toolbar or Home, or press **Command-N**.
2. Enter a task name, client, and notes. Choose **Start Watch** and pick what to record.
3. Do the task. Watch lists each recorded step (see `watch.md`). Add a note, stop,
   then choose **Review**. The review shows the recording's size and a sample procedure
   (learning from the recording comes next); edit the name, client, and notes, then save.
4. Choose **Complete sample**, then **Rehearse sample**. Inspect the receipt and expand the report.
5. Choose **Try another case**, select **Missing ad spend**, and rehearse again. Total spend and cost per lead remain missing. The report is an incomplete draft.
6. Optionally export Markdown to a local location you select. The app reads the saved file back and compares its contents with the sample report.

Watch is one shared session across the main window and the notch. Starting from either
surface updates the other. Rehearsing plays in the notch (about 5 seconds), then opens the receipt. Navigating away, closing the workspace, or opening the
teaching flow again does not restart it. Watch notes copy into sample review without
duplicates. Saving a skill shows "New skill" in the notch for a few seconds.

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
- Supabase sign-in and account storage are written but unverified end to end: the Supabase project doesn't exist yet.

The capture experiment and held-out evaluation data remain separate and unchanged.

## Regression checks

From `apps/mac/`, compile the isolated sample domain checks:

```sh
swiftc Sources/Understudy/Library.swift Tests/PrototypeChecks.swift -o /tmp/understudy-prototype-checks
/tmp/understudy-prototype-checks
```

These check missing-value propagation, simulation disclosure, and serialized receipt preservation. They do not test AI learning.

## Shared Watch checks

```sh
swiftc apps/mac/Sources/Understudy/Library.swift apps/mac/Sources/Understudy/WatchSession.swift apps/mac/Sources/Understudy/WorkspaceState.swift apps/mac/Tests/WorkspaceChecks.swift -o /tmp/understudy-workspace-checks
/tmp/understudy-workspace-checks
```

Notch strip checks (states, row order, read-only rehearsal, missing-spend receipt):

```sh
swiftc -parse-as-library apps/mac/Sources/Understudy/{Library,WatchSession,WorkspaceState,NotchActivity}.swift apps/mac/Tests/NotchChecks.swift -o /tmp/understudy-notch-checks
/tmp/understudy-notch-checks
```

The workspace checks cover resuming without resetting progress, app navigation, stopping into
review, carrying an unsubmitted note forward, and preventing duplicate notes.

## Verification on 2026-09-23

- Release build with `apps/mac/scripts/bundle.sh` passed. Bundle signature and plist
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
