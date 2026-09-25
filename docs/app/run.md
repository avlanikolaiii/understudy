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

## Reliability

- **No fixed pauses for elements.** A step that presses or clicks into something runs as soon as it appears, waiting up to its timeout (10 s by default). Keys and typing keep a short pause (at most 2 s) for the app to settle.
- **Results are read back.** After a press, a run looks for what should change: a toggle's other state ("Pause" after "Play"), or a heading or window title with the pressed item's name ("Bloom opened"). Then the receipt says *Verified* instead of *Not verifiable*. ↩ in a field is verified when the field's text changes.
- **A control that changed a little is still found.** If nothing matches exactly, a run looks for one control of the same kind, in the same place (context), whose name is the recorded one plus more words ("Bloom" → "Bloom (Deluxe)", never "Play" → "Playlist"). The receipt says so. If more than one could be it, the step is blocked: it never guesses.
- **Run again from the step that stopped.** A stopped or blocked run's receipt offers **Run again from step N** once you've fixed the cause; the steps before it aren't repeated.
- **Wait until…** steps (text shows in an app, or a number of seconds) can be added by hand.

Measured live on Spotify: the "Bloom" album heading is recognized as the result of pressing Bloom; "Bloom Album • Caligula's Horse" is found exactly; the short name "Bloom" finds two possible matches, so it isn't guessed.

## Editing a skill

- **Add step** (the **+** before any step, or at the end), in the Teach review and in **Edit**: open an app, press keys (recorded from your keyboard), type text, wait until a text shows, wait some seconds, or open a link or file (`https://…`, `spotify:…`, a path).
- **Record this step** (the ● on a step, in **Edit**): Watch records a new take; when you stop, its steps replace just that step.
- **Values asked when it runs:** write `{name}` in what a step types or opens (e.g. `Hello {client}`, `spotify:album:{album}`). **Edit** sets each value's default; **Run now** asks for them; a *file added* trigger fills `{file}` and `{fileName}`; schedules use the defaults.
- **The moment in the recording:** each recorded step shows the frame of its video at that moment (made on this Mac, kept next to the recording), so you see exactly what was clicked.

## Running

Skills → **Run now** or **Test step by step** (every step waits for "Run this step").

- One run at a time. A run never starts while Watch is recording, and Watch doesn't start during a run: the run's keystrokes would end up in the recording.
- A step that can't run, or fails (for example, a button that isn't found within its wait, or a field the app won't let Understudy click into), stops the run. Nothing after it is guessed. After **Stop**, nothing from that run acts any more, even a step that was waiting.
- A step that sends, pays, or deletes pauses the run until **Approve** or **Skip step**, in the run panel or right in the notch (which also has **Stop** while a run goes). That includes buttons named that way (Send, Pay, Delete, in English or Spanish) and keys that send or delete in common apps: ⌘↩ and Mail's ⇧⌘D send; Delete, ⌘⌫, ⇧⌘⌫, and # (Gmail, Superhuman) delete. The notch shows **Needs your OK**; clicking it opens the run.
- It never moves the mouse. It does bring apps to the front and type, so it uses the keyboard while it runs.

Every run ends with a receipt (`kind = run`): each step's status (Done, Skipped, Blocked, Failed, Not run) and, separately, its evidence (Verified, Not verifiable, with what was checked). For example, "Opened Superhuman" is verified by reading which app is in front; a pressed button is "Not verifiable" because what it did can't be read back.

## App commands

Some apps have their own commands on the Mac. A step can use one instead of clicks: it doesn't look for anything on screen, so it works with the app's window moved, hidden, or minimized. Add step → **App command**:

| App | Commands |
|---|---|
| Spotify | Play a song, album, or playlist link; pause; next; previous |
| Music | Play a playlist; pause; next |
| Finder | Open a folder; show a file (for example `{file}` from a folder trigger) |
| Browser | Open a web link in the default browser, Safari, Chrome, Dia, or Arc |
| Mail | Create a draft (to, subject, message). It's never sent: sending stays a step that waits for your OK |

- The list is fixed (`AppCommand`). A step never runs a script someone wrote, and values can't add code to one: they're checked (a Spotify link must be a Spotify link, an address an address) and quoted.
- Spotify, Music, and Mail commands run through AppleScript. The first time, macOS asks to let Understudy control that app (System Settings → Privacy & Security → Automation). Finder and browser commands only ask macOS to open something.
- The receipt reads the result back: for example, "Playing: Bloom — Caligula's Horse" makes the step *Verified*.
- **Spotify's own command instead of clicks:** when a skill's steps click in Spotify, the step list offers **Use Spotify's own command instead**. Start the song or album in Spotify and press it: Understudy reads what's playing and replaces the Spotify clicks with one step that plays it by its link. To play a whole album or playlist, paste its link into that step (Share → Copy link).

## Starting a skill from anywhere

- **A shortcut per skill:** in Skills, under the run buttons, **Set shortcut** and press the keys (for example ⌥1). It must include ⌘, ⌥, or ⌃. It can't be the Watch shortcut or another skill's. Pressing it runs the skill at once. Shortcuts are kept on this Mac.
- **The notch menu:** click the notch while it's at rest and it opens into a menu of the skills with steps, as tiles, plus **Teach** and **Open Understudy** (see [interface-prototype.md](interface-prototype.md)). A skill chosen there starts right away (or next, if another is running). Only triggers count down and wait for you to pause.
- **The quick launcher:** press ⇧⌥Space anywhere (or menu bar → **Run a Skill…**). Type part of a skill's name (its start, a word, or letters in order, like "pb" for Play Bloom), pick with ↑↓, and ↩ runs it at once. A skill with `{values}` asks for them first, filled with its defaults (⇥ moves between them). Esc goes back or closes; clicking elsewhere closes it. It also offers **Teach a skill** and **Open Understudy**. ⇧⌥Space can't be taken by a skill's shortcut.
- **Links:** `open "understudy://run?skill=Play%20Bloom"` from Terminal, Shortcuts, Raycast, or Alfred. `skill` is the skill's name or id. Any other query items fill its values, for example `&album=Bloom`. A run started by a link starts right away, like the others you start yourself. A link to a skill that doesn't exist runs nothing, and the notch says so.
- **Notifications:** when a run ends, or waits for your OK, macOS shows a notification (Understudy asks for permission the first time). Clicking it opens the receipt, or the run that waits.

## When it runs

Skills → **When it runs**:

- Only when you start it
- On a schedule: a time, every day or on chosen days
- Every few hours
- When an app opens
- When a file is added to a folder

Triggers run on the Mac where they were set (`Trigger.device`), while it's awake, you're logged in, and Understudy is open. **Open at login** keeps them working after a restart. A scheduled run the Mac slept through runs when it wakes, if it is less than 2 hours late, once.

A waiting run is dropped if its skill is deleted, loses its trigger, or its account signs out; when its turn comes, it runs the skill as it is then, with any edits. Before a triggered run, the notch counts down for 10 seconds ("Running in 10s"). Clicking the notch or pressing the shortcut cancels it. If you're typing or clicking, the run waits until you pause for a minute (at most 10 minutes). If it can't start (Watch is recording, or Accessibility is off), the notch says why.

## Tests

- `RunChecks`: order, recorded pauses, approval, skip, blocked and failed steps, step by step, cancel with a late answer.
- `StepsChecks`: a take shaped like a real one becomes the expected steps; approval words; unsupported steps.
- `TriggerChecks`: schedules on chosen days, month end, daylight time, catch-up, intervals, events, the old format.
- Self-test: runs, approvals, skips, stops, receipts, triggers firing with the countdown, and cancelling it, with a scripted performer. Invariants: a sending step never runs without approval; every run saves exactly one receipt; a run and Watch never overlap; no run during a countdown.

Real runs need Accessibility access and real apps, so they are verified by hand: see the pull request's checklist.
