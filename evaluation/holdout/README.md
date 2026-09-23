# Held-out evaluation data: do not open during development

These weeks are the unseen examples for the pass/fail tests. If a developer or the learning code reads them before testing, the test no longer measures learning.

| Folder | Used for |
|---|---|
| `week-04`–`week-06` | Blind rehearsal (T2) and read-only check (T3) |
| `week-07` | Missing-figure test (T4). Video spend is blank |

Each folder has:
- `sheet/`: the campaign sheet as it looked that Monday, including earlier weeks. This is the only thing Understudy gets during a rehearsal.
- `expected/`: the report the agency would have sent. It's used only to score results after Understudy's version is finished.

Rules:
1. Learning and development code must never read from `evaluation/`. The test harness is the only thing that reads here.
2. Don't edit these files. `MANIFEST.sha256` lets you detect changes: `cd evaluation/holdout && shasum -a 256 -c MANIFEST.sha256`
3. Numbers are scored against `docs/report-spec.md`. Summary, Highlight, and Next week are judged by a person. The expected text there is one acceptable answer, not the only one.
4. Passing three held-out weeks is an initial result, not proof of broad reliability.
