# Understudy

A Mac companion that learns a recurring task from one demonstration, rehearses it on examples it hasn't seen, and reports what it did and how it checked.

**Status: clickable native Mac interface prototype.** The app now opens a local workspace with guided sample teaching, saved sample skills, two rehearsal scenarios, receipts, and Markdown export. Recording, AI learning, and connected execution are not implemented by this interface. See [the interface guide](docs/interface-prototype.md) for build and usage instructions. The separate capture experiment remains on hold.

| Path | What's there |
|---|---|
| `app/` | Native SwiftUI app, local demo workspace, existing sign-in shell |
| `docs/interface-prototype.md` | What works, what is simulated, and how to try it |
| `docs/prototype-1.md` | Approved scope, proposed pass/fail criteria, milestones |
| `docs/report-spec.md` | Exact formulas, rounding, and the missing-data rule |
| `docs/capture-experiment.md` | M1: can a demonstration be captured? Protocol and results |
| `docs/validation/` | Customer-interview kit in English and Spanish (nothing sent yet) |
| `templates/weekly-update.md` | The fixed report template |
| `fixtures/teaching/` | Synthetic teaching data. Readable during development |
| `evaluation/holdout/` | Held-out weeks for testing only. **Don't open during development** |
| `tools/ax-capture/` | The capture experiment recorder |

Never commit client examples, credentials, or generated reports. `.gitignore` covers `client-examples/`, `runs/`, `out/`, and token files.
