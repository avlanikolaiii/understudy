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
| A · Native baseline | Teaching CSV in Numbers, report typed in TextEdit | Partly run (see results log) |
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

### 2026-09-23 · Phase A, runs 1–2 (interim)

**Setup.** The recorder was run from the Claude app's Terminal panel, which has Accessibility access. The demonstration was scripted with AppleScript, not done by hand: it selected week-1 ranges in Numbers (D5:D7, E5:E7, F5:F7, G5:G7, then F6) and wrote the week-1 report into `runs/demo-week-01.md` in TextEdit. The apps were in the background (not frontmost). A scripted demonstration is a stand-in for a human one. It changes the same app state, but it doesn't click or type.

**What we learned**

1. **The recorder's main path failed.** The system-wide "focused application" query returned `cannotComplete` even though the process was trusted. Run 1 logged only `focus: none`. Fix: fall back to the frontmost regular app, or watch named apps directly (`record-apps`).
2. **TextEdit: fully captured.** Document name, full text after each edit, and caret position (item 5, and item 1 for this app).
3. **Numbers, first look: grid not exposed.** The focused element was a generic scroll area whose only children were scrollbars. Cell selections produced no change. Numbers' status bar did show the selected cell's *value* (`793.32` = F6) but not its address.
4. **Screen-reader mode is unsupported.** Setting `AXEnhancedUserInterface` on Numbers returned `notImplemented`.
5. **Numbers, later look: grid exposed.** A later tree dump showed an `AXLayoutArea` containing an `AXTable` ("campaign_data, 13 rows, 7 columns") with every row and column (column descriptions = header names) and `selectedCells=1`. Numbers appears to build its accessibility tree lazily once a client starts asking. This needs confirming: what triggers it, and does it survive relaunching Numbers?

**Scoring so far (phase A)**

| Item | Status | Evidence |
|---|---|---|
| 1 · App and document | Captured | `app`, `window` = `campaign_data` / `demo-week-01.md` |
| 2 · Sheet tab | Partly | "Sheet 1" appears in the tree; not yet tied to the selection |
| 3 · Selected cell address | Not yet shown | Table exposes `selectedCells`. The recorder now reads cell addresses from row and column indexes, but that isn't verified yet (run 3) |
| 4 · Cell values | Partly | Selected value via the status bar (`793.32`) |
| 5 · Typed text and where | Captured | TextEdit value and caret range after each edit |

**Next:** run 3 with the table-selection reader. Then repeat with Numbers freshly relaunched, to test whether the grid is exposed from the start or only after it's first queried. Then do phase B (Google Sheets), which needs a test spreadsheet.
