# Prototype 1: the weekly client update

**Scope approved 2026-09-23. The pass/fail criteria below are proposed and not yet agreed.**

The question this prototype answers: can one demonstration become a reusable procedure that gets a week it has never seen right? A preprogrammed reporting script would test plumbing, not Understudy's central claim.

## In scope

- One workflow: the weekly client update.
- One input: a Google Sheet, read-only. During development it's a local CSV (`data/fixtures/`), and a dedicated test spreadsheet is created only when the connector experiment needs it.
- One output: a Markdown report from `data/templates/weekly-update.md`. PDF export comes after the content tests pass.
- Learning from one demonstration, blind rehearsal, a missing-figure test, and a basic receipt.
- A sample-data first run that needs no connected accounts.
- A minimal notch or menu-bar panel to start and stop.

## Later

Tracker updates, client email, other connectors and MCP, client-wide and global corrections (edits apply to this workflow only for now), voice start, cloud AI, scheduled runs, sync, team features, receipt dashboards.

## Rules that hold for every test

- **Teaching and evaluation stay separate.** Only `data/fixtures/teaching/` is available during development. `data/evaluation/holdout/` (weeks 4–7: both the input sheets and the expected reports) is read only by the test harness. See its README.
- **Read-only means every connected account.** During rehearsal, Understudy must not modify any live sheet, document, draft, file, or other account data. It may write only to an isolated local output folder (`runs/`). Where possible this is enforced with read-only credentials, not just avoided.
- **Numbers are exact under `docs/report-spec.md`.** Source figures must equal the sheet. Calculated figures must follow the spec's formulas and decimal half-up rounding.

## Proposed pass/fail criteria

| Test | Setup | Passes when |
|---|---|---|
| T1 Learn | One demonstration of week 1 | A skill file comes out with zero hand edits to its steps or logic |
| T2 Rehearse | Weeks 4–6, held out. Input sheet only | Every number is exact per the spec. All template sections are filled. *Judgment:* the narrative is acceptable in at least 2 of 3 weeks |
| T3 Read-only | During T2 | Zero changes in any connected account, verified by revision history or an audit log. Local outputs only |
| T4 Missing figure | Week 7, held out (Video spend blank) | Title marked incomplete, missing cell named, dependent figures marked, nothing invented, and the receipt shows the step as blocked |
| T5 Receipt | Every run | Status and evidence are recorded separately, and the evidence matches the output file on inspection |
| T6 First run | A clean Mac, no accounts | A new person completes the sample run in 5 minutes or less without help. *Judgment:* they can say what happened |

Three held-out weeks passing is an initial result, not evidence of broad reliability.

## Milestones

1. **M0 · Fixtures** (done): synthetic teaching and held-out data, report spec, template.
2. **M1 · Capture experiment** (in progress): see `docs/capture-experiment.md`. Report the result before expanding the build.
3. **M2 · Learn:** event log → skill file (T1).
4. **M3 · Run and receipt:** on the teaching sheet (T5).
5. **M4 · Rehearsal and missing figure:** on the held-out weeks (T2–T4).
6. **M5 · First-run package** (T6). Markdown to PDF export after this.
