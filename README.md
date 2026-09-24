# Understudy

A Mac companion that learns a recurring task from one demonstration, rehearses it on examples it hasn't seen, and reports what it did and how it checked.

**Status: clickable native Mac interface prototype.** One app: a main window (teach, skills, receipts, account) and a live notch strip styled after the landing page. It runs in Sample mode on this Mac until you sign in. It includes guided sample teaching, two rehearsal scenarios, receipts, and Markdown export. Recording, AI learning, and connected execution are not implemented by this interface. See [the interface guide](docs/app/interface-prototype.md) for build and usage instructions. The separate capture experiment remains on hold.

| Path | What's there |
|---|---|
| `apps/mac/` | Native SwiftUI app: main window, notch strip, Sample mode + Supabase account |
| `AGENTS.md`, `CLAUDE.md`, `docs/worklog.md` | Shared rules and work log for Codex and Claude Code |
| `docs/app/interface-prototype.md` | What works, what is simulated, and how to try it |
| `docs/product/prototype-1.md` | Approved scope, proposed pass/fail criteria, milestones |
| `docs/product/report-spec.md` | Exact formulas, rounding, and the missing-data rule |
| `docs/research/capture-experiment.md` | M1: can a demonstration be captured? Protocol and results |
| `docs/research/validation/` | Customer-interview kit in English and Spanish (nothing sent yet) |
| `data/templates/weekly-update.md` | The fixed report template |
| `data/fixtures/teaching/` | Synthetic teaching data. Readable during development |
| `data/evaluation/holdout/` | Held-out weeks for testing only. **Don't open during development** |
| `tools/ax-capture/` | The capture experiment recorder |

Never commit client examples, credentials, or generated reports. `.gitignore` covers `client-examples/`, `runs/`, `out/`, and token files.
