# Work log: Claude Code + Codex

Both agents work in this repo. Read this file and `git status` before starting.

**Now working:** nobody. Claim this line before you edit anything.

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

## 2026-09-23 19:02 · Codex · Pure Decimal weekly report engine
- commits: none. Git staging was blocked by the sandbox: `fatal: Unable to create '/Users/nikolai/Developer/understudy/.git/index.lock': Operation not permitted`. The three assigned files remain uncommitted; no other agent's files were staged or changed.
- what: `ReportEngine.report(csv:week:client:agency:)` returns a Sendable `WeeklyReport` with Markdown, source-data completeness, missing cells, and typed unrounded figures for both weeks and their changes. Foundation only; deterministic dates/table; explicit AI placeholders; no file or network access. API and input rules are in `docs/report-engine.md`.
- verified: the exact requested `swiftc` command and executable passed all five check groups. Swift 6 strict concurrency with warnings-as-errors also passed. Teaching weeks 1, 2, and 3 match the fixture titles, dates, and all table lines exactly. Synthetic checks cover half-up ties (including signed changes and repeating rates), sum-before-rounding, blank Video spend and dependent values, other missing cells, zero leads/spend, missing/zero/absent prior figures, CSV normalization, deterministic row order, and invalid input. Whitespace checks passed. No spec/fixture disagreements. No held-out data was accessed.
- not verified: app integration, app bundle, Supabase, Google Sheets, AI proxy, output-file read-back, tracker/email behavior, or receipt persistence. `isComplete` concerns source figures only; all three judgment sections still show `[AI step: not connected yet]`.
- next: commit the engine/checks, then docs/worklog from a session allowed to write Git metadata; end each commit message with `Co-Authored-By: Codex <noreply@openai.com>`. Wire the engine into the app in the next authorized slice, keeping missing-data gating and AI placeholders visible.

## 2026-09-23 19:45 · Claude Code · Live Supabase project + Codex's report engine committed
- commits: 297261a (Codex's engine, committed for it; the Codex sandbox can't write .git), 7b63cd5 (grants migration), plus this docs commit.
- what:
  - Created the Supabase project `Understudy` (idwgaqnpheittqtllhzl, sa-east-1) in the human's account.
  - Applied migrations 0001–0003 through the SQL editor.
  - Revoked anon access.
  - Allowed `understudy://auth-callback`.
  - Wrote `app/config.local.json` with the publishable key only.
  - Rebuilt the app.
- verified:
  - SQL catalog: 3 tables with RLS and 1/4/2 policies, the free-limit trigger, the sign-up trigger, authenticated grants, and no anon grants.
  - Live API: `/auth/v1/settings` says email on, Google/Apple off, sign-up allowed. A signed-out read of `skills` returns 401 permission denied.
  - Codex's ReportChecks re-run by Claude: 5/5 pass. Codex's log has no commands touching `evaluation/`.
- not verified: an actual sign-in from the app (needs the human's email inbox), and a skill/receipt round trip to the account.
- note for Codex: `codex exec -s workspace-write` can't commit. Leave the files uncommitted plus a worklog entry, and Claude or the human commits them.
- next: the human tests email-link sign-in. Then wire ReportEngine into rehearsal (real numbers from fixtures/teaching instead of SampleEngine), then Google sign-in.

## 2026-09-23 20:40 · Claude Code · Pre-launch site live on Vercel, with a waitlist
- live: https://understudy-nine-dusky.vercel.app (Vercel project `understudy`, team nicolas-leons-projects; deploy with `cd web && npx vercel deploy --prod`)
- commits: 76d36fd (site + 0004), 7466a22 (Codex review fixes + 0005), and this log commit.
- what:
  - `web/` is a static site with no dependencies (`node build.mjs`).
  - Home is only the hero (the human's screenshot, dark palette). Each menu item has its own page, plus privacy and 404.
  - All download mentions were removed, at the human's request.
  - Waitlist in Supabase via `join_waitlist` / `add_waitlist_details`. The table itself has no API access.
- verified:
  - All 9 pages return 200 publicly (404 for unknown routes), with the CSP and nosniff headers.
  - Supabase CORS preflight from the site's origin returns 200.
  - Local checks:
    - No horizontal overflow at 375 px on all 8 pages.
    - The menu is visible on mobile, and the right item is marked current.
    - Form flows are correct with a mocked server.
  - Live DB (anon role, in transactions that were rolled back): reads and direct inserts refused, bad email rejected, details saved once, two-tab join keeps the token.
  - The waitlist has 0 rows.
- reviewed: `codex exec review` found 4 P2 issues (hidden states, two-tab token, enumeration, blocked storage). All fixed.
- not verified: a real signup from the live site (that would add a real row), and how it looks in browsers other than the pane.
- open: the privacy page still needs a contact email from the human before wider sharing.

## 2026-09-23 20:55 · Claude Code · App icon = the website's favicon mark
- commits: the one that adds `app/Resources/AppIcon.icns`.
- what: `app/scripts/make-icon.swift` draws the favicon (dark rounded square #101217, yellow dot #F4C534, same proportions) on Apple's 824/1024 icon grid. `iconutil` builds the .icns. `bundle.sh` copies it and sets `CFBundleIconFile`.
- verified: the bundle builds and its signature verifies. `NSWorkspace.icon(forFile:)` returns the new icon, with macOS 26's glass treatment applied.
- not verified: how the Dock and Finder look on screen (my screenshots of other apps are unreliable). The menu bar item still uses the theater-masks symbol.

## 2026-09-23 21:05 · Claude Code · Icon now glows like the website header logo
- what: the app icon and the favicon now draw the header's `.bulb`: dot, 30% ring, and 55% glow in dark-mode yellow #E0B22A on #101217. Both were redeployed and rebuilt.
- verified: macOS returns the new icon for the bundle, and the live site serves the new favicon.
