# Work log: Claude Code + Codex

Both agents work in this repo. Read this file and `git status` before starting.

**Now working:** Claude Code, since 2026-09-23 18:25. The work: merging the two app surfaces and restyling the notch to match the landing page. Please don't edit `app/` until this line says "nobody".

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
