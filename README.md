# Understudy

A Mac companion that learns a recurring task from one demonstration, rehearses it on examples it hasn't seen, and reports what it did and how it checked.

**Status: product concept.** Nothing in the product works yet. This repo holds the first prototype's fixtures, specs, and experiments.

| Path | What's there |
|---|---|
| `docs/prototype-1.md` | Approved scope, proposed pass/fail criteria, milestones |
| `docs/report-spec.md` | Exact formulas, rounding, and the missing-data rule |
| `docs/capture-experiment.md` | M1: can a demonstration be captured? Protocol and results |
| `docs/validation/` | Customer-interview kit in English and Spanish (nothing sent yet) |
| `templates/weekly-update.md` | The fixed report template |
| `fixtures/teaching/` | Synthetic teaching data. Readable during development |
| `evaluation/holdout/` | Held-out weeks for testing only. **Don't open during development** |
| `tools/ax-capture/` | The capture experiment recorder |

Never commit client examples, credentials, or generated reports. `.gitignore` covers `client-examples/`, `runs/`, `out/`, and token files.
