# Work log: Claude Code + Codex

Both agents work in this repo. Read this file and `git status` before starting.

**Now working (split, since 2026-09-23 19:20):**
- **Claude Code:** the Supabase setup. Files: `supabase/`, `docs/setup/`, `app/config.local.json`, `AppModel.swift`, `SkillLibrary.swift`, `AccountView.swift`, `Config.swift`, `scripts/bundle.sh`.
- **Codex (`codex exec`, started by Claude at the human's request):** the report engine. Files: new `app/Sources/Understudy/ReportEngine.swift`, `app/Tests/ReportChecks.swift`, `docs/report-engine.md` only.

Don't edit the other agent's files until its line is released.

---

Entries are append-only, newest last. Use this format:

```
## YYYY-MM-DD HH:MM · <agent> · <one-line summary>
- commits: <hashes>
- verified: <what you actually ran or saw>
- not verified: <what you didn't check>
- next: <what should happen next>
```

## 2026-09-23 08:00 · Claude Code · Prototype 1 set up
- commits: 046ea4c, ec03707
- verified: fixtures regenerated from the report spec; the ax-capture recorder builds.
- not verified: capture phase A analysis (paused).
- next: the app prototype.

## 2026-09-23 08:33 · Claude Code · App slice 1: notch panel and Supabase sign-in
- commits: 8aac6ad, 6ddbc83 (AGENTS.md handoff)
- verified: the release build; the notch pill placed over the notch on this MacBook.
- not verified: every sign-in flow, because the Supabase project doesn't exist yet.
- next: Watch (simulated).

## 2026-09-23 13:44 · Codex (thread 1, cwd "AI Startup") · Local interface prototype
- commits: none of its own; the files were committed later inside baddea5, and README/bundle.sh were committed as d199722.
- what: a separate workspace window with Home, Teach, My skills, and Run results. It saved local sample skills and receipts to `~/Library/Application Support/Understudy/interface-prototype.json`.
- note: this created a second skill list and a second set of receipts next to the account-backed notch. That's the "two apps" problem.

## 2026-09-23 14:06 → 23:07 UTC · Codex (thread 01a0ce82…, cwd understudy) · Watch, shortcut, and a native workspace
- commits: 787266e, 6c6a755, 4a7f296, baddea5
- verified: the release build, signature, and plist; the Watch, workspace, shortcut, and prototype checks; launching Watch from the app; note entry; settings.
- not verified: end-to-end notch and global-shortcut interaction; dark mode; the no-notch fallback.

## 2026-09-23 18:25 → 19:10 · Claude Code · One app, a landing-page notch, and a shared brain
- commits: d199722 (Codex's leftover README/bundle.sh, saved as-is), 1f9e52b (the merge), b21659a (AGENTS/CLAUDE/worklog/docs), and the latest fix commit (Codex review fixes)
- what:
  - The main window is the one home, with a new Account page.
  - The notch is the landing page's live strip.
  - SkillLibrary: Sample mode before sign-in, the Supabase account after.
  - Migration 0002.
  - `--notch-demo`.
- verified:
  - The release bundle builds and its signature verifies.
  - Prototype, Workspace, Watch, Notch (new), and Shortcut checks all pass.
  - `--notch-demo` screenshots of the real notch window match the page's Watching, Rehearsing, Running, and Receipt states.
  - A window probe showed a 268×38 pill over the 208×38 notch, growing row by row (69→141 px) and shrinking back 0.6 s after closing.
  - The idle pill was screenshotted.
- reviewed: `codex exec review --commit 1f9e52b` found 2 P1 (account load and rehearsal owner races) and 2 P2 (account rehearsal before load; shortcut under an overlay). All four are fixed.
- not verified:
  - The main window visually (screen capture failed for it).
  - The shortcut and clicks end to end.
  - Reduce Motion.
  - The no-notch fallback.
  - Every signed-in flow, because Supabase isn't set up.
- next: the human sets up Supabase (docs/setup/accounts.md, including migration 0002). Then the approved Skill review slice (editable rules saved to `skills.definition`).
