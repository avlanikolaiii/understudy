# M1: capture experiment

**Question:** when someone does the weekly update once while Understudy watches, can the Accessibility API tell us, precisely enough to build a skill from:

1. which app and document they're in,
2. which sheet tab,
3. which cells they selected (address or row and column),
4. the values in those cells,
5. what they typed into the report, and where?

If any of these can't be captured, we write down exactly what's missing before choosing a fallback. Asking the user to select a sheet or range explicitly is one possible fallback. It changes the "just watch me" promise, so it's a product decision, not a technical detail.

## Status

| Phase | Setup | Status |
|---|---|---|
| A · Native baseline | Teaching CSV in Numbers, report typed in TextEdit | Ready to run once Accessibility access is granted |
| B · Google Sheets in a browser | A dedicated test spreadsheet in Chrome and Safari | Waiting: needs approval to create the test spreadsheet |
| C · Sheets with screen-reader support on | Same as B, with Google Sheets' own accessibility setting turned on | After B |

## Running it

1. Build: `tools/ax-capture/build.sh`
2. Grant access: System Settings → Privacy & Security → Accessibility → turn on **Terminal**. Run the tool from your own Terminal. That's narrower than giving the Claude app control of your Mac.
3. Check: `tools/ax-capture/ax-capture check` should print `TRUSTED`.
4. Record: `tools/ax-capture/ax-capture record runs/phase-a.jsonl`, then do the demonstration and press Ctrl-C when you finish.

Logs go to `runs/`, which git ignores. Password fields are recorded by role only, never by value.

### Phase A demonstration script (about 3 minutes)

1. Open `fixtures/teaching/sheet/campaign_data.csv` in Numbers.
2. Open `templates/weekly-update.md` in TextEdit. Save a copy as `runs/demo-week-01.md`.
3. In Numbers, click each week-1 cell you'd use: impressions, clicks, spend, and leads for all three channels.
4. In TextEdit, type the week-1 totals into the Numbers table and write one sentence for Summary.
5. Stop recording.

## Scoring

For each of the five items, mark **Captured**, **Partly**, or **Not captured**, and paste the log line that shows it.

| Item | Phase A | Phase B (Chrome) | Phase B (Safari) | Phase C |
|---|---|---|---|---|
| 1 · App and document | | | | |
| 2 · Sheet tab | | | | |
| 3 · Selected cell address | | | | |
| 4 · Cell values | | | | |
| 5 · Typed text and where | | | | |

## Hypothesis to test, not a finding

Google Sheets draws much of its grid itself instead of as standard page elements, so the Accessibility API may expose little about which cell is selected unless the Sheets screen-reader setting is on. Phase B tests this directly. Until it's measured, treat it as a risk, not a result.

## Results log

_No runs yet._
