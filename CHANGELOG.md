# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The project has no tagged releases yet.

## [Unreleased]

### Mac app (`apps/mac`)
- A single app with two surfaces: the main window (Home, Teach a skill, Skills, Receipts, Account) and a live strip in the notch that is styled and animated like the website's hero demo.
- One data layer (`SkillLibrary`). **Sample mode** stores skills and receipts on the Mac before sign-in. After sign-in, the Supabase account stores them.
- Supabase Auth with Google, Apple, and email-link sign-in (PKCE, `understudy://auth-callback`). Email sign-in is configured; Google and Apple are not yet.
- **Watch records for real:** a screen video (ScreenCaptureKit, through macOS's picker) and an action log (apps, clicked controls, typed text per field, shortcuts, spreadsheet selections) through Accessibility. Recordings stay on the Mac; password fields are never recorded. Without Accessibility access, Watch says why and links to the setting. It replaces the predefined five-step replay and is shared between the notch and the main window.
- Simulated rehearsal and receipts for a complete week and a week with missing ad spend. Markdown export reads the file back after writing it.
- A configurable global shortcut (default ⌥ Space) with a native recorder.
- `ReportEngine`: a pure-Foundation weekly report with `Decimal` math and half-up rounding that follows `docs/product/report-spec.md`. It matches teaching weeks 1–3 exactly and is not wired into the app yet.
- App icon: the website's glowing dot.
- `--notch-demo` launch flag that replays the website's hero sequence in the real notch.
- `UnderstudyCore`, a pure-Swift module for models and engines. `SkillDefinition` v1 is the skill format the app will run itself: trigger, inputs, steps (executor, target, effect, evidence), rules, and output, with a schema version. Older formats migrate; newer ones are refused.
- The account (`AccountStore`) and the Mac's versioned file (`LocalStore`) are separate stores. `AppEnvironment` creates the app's objects once.
- A fixed self-signed signing identity (`scripts/make-signing-identity.sh`), so macOS keeps the app's permissions across builds. The app is now a regular Dock app, as it already behaved.

### Website (`apps/web`)
- A static pre-launch site with no dependencies. The home page is the hero only, and each menu item has its own page (workflow, rehearsal, receipts, what exists, pricing, early access), plus privacy and 404 pages.
- An early-access waitlist stored in Supabase through two narrow functions. The table itself has no public access.
- Strict security headers (CSP, `nosniff`) and clean URLs on Vercel.

### Backend (`supabase/migrations`)
- `0001` profiles, skills, and receipts with row-level security, a sign-up trigger, and a server-side free-plan limit of 5 skills.
- `0002` receipt details (skill name, client, report, simulated flag).
- `0003` explicit Data API grants for signed-in users; none for anonymous users.
- `0004`–`0005` the waitlist table and its `join_waitlist` / `add_waitlist_details` functions. They reveal nothing about existing signups and keep an outstanding token across repeated joins.

### Quality
- `qa/run.py`: one command runs the checks, simulated-user sessions on the real app (`--self-test`), website QA, and held-out evals. It draws a coverage graph and a trend report.
- The report engine matches all four held-out weeks exactly, including the week with missing spend.
- CI builds the app once and runs that same bundle on fresh macOS 14, 15, and 26 machines for every pull request: simulated users plus a real first launch.

### Research and data
- Synthetic agency fixtures (teaching weeks 0–3) and held-out evaluation weeks 4–7 with a SHA-256 manifest.
- A report spec with exact formulas, rounding, and the missing-data rule.
- The capture experiment (`tools/ax-capture`) and a customer-interview kit in English and Spanish. Both are paused.
