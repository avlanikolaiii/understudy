# Running a skill, and when it runs

A skill is the recorded steps of a task. Understudy runs them itself on this Mac, exactly as they were done: no AI yet (that comes with learning, which will generalize steps and write the judgment parts).

## From recording to steps

`StepsFromRecording` (`UnderstudyCore`) turns each recorded action into one step:

| Recorded | Step | How it runs |
|---|---|---|
| Dock click on an app, or switching to it | Open the app | Opens it by bundle id and checks it came to the front |
| Click on a control (button, menu item, tab, link, row) | Press "Play" ("Bloom") | Finds it by identifier, or by role, name, and the text around it (its context), through Accessibility, and presses it. Never by position: moving or resizing the window doesn't matter. A double-click presses twice |
| Click into a named field | Click in "Subject" | Focuses the field |
| Typing into a text field | Type "open" | Types the text as Unicode key events into the app in front |
| A key or shortcut (↩, ⇥, ⌘K), or a letter pressed outside a text field (E to archive) | Press ⌘K, Press E | Posts exactly that key (its recorded key code) with its modifiers |
| Click on something without a name, a cell selection, a password | Can't run yet | Shown in the review with the reason |

Rule: a key pressed where no text field had focus is never replayed as text, and a run never clicks into or types into a field unless the recording did. Older recordings that saved such keys as typing (for example "gi" in an inbox) become one key press per letter.

Apps built on Chromium can hide what's inside their windows. Electron apps show it once Understudy asks. Apps on the Chromium Embedded Framework, like Spotify, show it only when opened with `--force-renderer-accessibility`: a click in such an app is marked in the review with **Reopen for Understudy**, and a run's "Open" step reopens the app that way when it needs to. Measured on Spotify: 17 elements were found again out of 18 sampled (nine "Play" buttons told apart by their albums) after moving and resizing the window. The one miss was a row whose content hadn't loaded, which becomes a step that can't run.

The pause before each step is the one in the recording, between 0.3 and 5 seconds. Controls whose name means sending, paying, or deleting (Send, Enviar, Pay, Delete, Borrar, …) and ⌘↩ wait for approval.

The review lists the steps; each can be deleted, moved up, or retyped. They are saved with the skill (`skills.definition`) along with the recording's id. A skill saved before steps existed can get them from the latest recording on the Skills page.

## Running

Skills → **Run now** or **Test step by step** (every step waits for "Run this step").

- One run at a time. A run never starts while Watch is recording, and Watch doesn't start during a run: the run's keystrokes would end up in the recording.
- A step that can't run, or fails (for example, a button that isn't found within 5 seconds), stops the run. Nothing after it is guessed.
- A step that sends, pays, or deletes pauses the run until **Approve** or **Skip step**. The notch shows **Needs your OK**; clicking it opens the run.
- It never moves the mouse. It does bring apps to the front and type, so it uses the keyboard while it runs.

Every run ends with a receipt (`kind = run`): each step's status (Done, Skipped, Blocked, Failed, Not run) and, separately, its evidence (Verified, Not verifiable, with what was checked). For example, "Opened Superhuman" is verified by reading which app is in front; a pressed button is "Not verifiable" because what it did can't be read back.

## When it runs

Skills → **When it runs**:

- Only when you start it
- On a schedule: a time, every day or on chosen days
- Every few hours
- When an app opens
- When a file is added to a folder

Triggers run on the Mac where they were set (`Trigger.device`), while it's awake, you're logged in, and Understudy is open. **Open at login** keeps them working after a restart. A scheduled run the Mac slept through runs when it wakes, if it is less than 2 hours late, once.

Before a triggered run, the notch counts down for 10 seconds ("Running in 10s"). Clicking the notch or pressing the shortcut cancels it. If you're typing or clicking, the run waits until you pause for a minute (at most 10 minutes). If it can't start (Watch is recording, or Accessibility is off), the notch says why.

## Tests

- `RunChecks`: order, recorded pauses, approval, skip, blocked and failed steps, step by step, cancel with a late answer.
- `StepsChecks`: a take shaped like a real one becomes the expected steps; approval words; unsupported steps.
- `TriggerChecks`: schedules on chosen days, month end, daylight time, catch-up, intervals, events, the old format.
- Self-test: runs, approvals, skips, stops, receipts, triggers firing with the countdown, and cancelling it, with a scripted performer. Invariants: a sending step never runs without approval; every run saves exactly one receipt; a run and Watch never overlap; no run during a countdown.

Real runs need Accessibility access and real apps, so they are verified by hand: see the pull request's checklist.
