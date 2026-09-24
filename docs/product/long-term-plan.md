# Long-term plan

How Understudy grows from today's prototype to a product. It separates the code that exists
to show the idea now from the architecture that has to last, and it orders the work.

## The MVP

The MVP is the launchable version of [Prototype 1](prototype-1.md): one workflow, the weekly client update, on a person's own Mac.

- An open-source download (self-signed, not notarized) that a person can open on a clean Mac by following the first-launch steps.
- A first run on sample data with no accounts: rehearsal and a receipt in under 5 minutes (T6).
- **Teach:** one real, recorded demonstration of the update becomes a skill with no hand edits (T1). Understudy records the screen and the actions (which button, which field, which value) only while the person teaches.
- **Rehearse:** read-only, blind, on held-out weeks, with exact numbers (T2, T3). A missing figure is blocked, never guessed (T4).
- **Run:** one Google Sheet in, one Markdown report out, and a receipt whose evidence is a read-back of the output (T5).
- **Account:** sign-in; skills, receipts, and connections in the person's cloud account.
- **AI:** Understudy Cloud by default, your own key, or Apple's on-device model. Understudy runs the skill itself; nothing is exported to another AI app.

Everything else in the roadmap below comes after the MVP.

## What is temporary today, and what replaces it

| Today | Why it exists | Replaced by | When |
|---|---|---|---|
| `WatchSession`: a fixed 5-step replay | Shows the Watch experience before capture works | **Capture:** a screen video (ScreenCaptureKit) and an action log of apps, clicked elements, fields, and values (from `tools/ax-capture`) | MVP |
| `SampleEngine`: fixed report text | Shows rehearsal and receipts on sample data | **RunEngine** driving `ReportEngine` on real inputs | MVP |
| `Skill` = name, client, notes | Enough to save and list skills | **SkillDefinition v1** (done): trigger, inputs, ordered steps, rules, and `schemaVersion`, stored in `skills.definition`. Learned steps fill it in | MVP |
| Notes stored, never applied | No learning yet | **Learning:** event log + notes → SkillDefinition, through the AI proxy, reviewed in Skill review | MVP |
| `interface-prototype.json` | Sample mode storage | `LocalStore` (done): versioned, migrates older files, refuses newer ones. Becomes the offline cache of the account | MVP |
| `SkillLibrary` calls Supabase directly | Fastest path to accounts | `AccountStore` (done) is the source of truth after sign-in | MVP |
| `AppDelegate` builds every object | A single-window prototype | `AppEnvironment` (done), used by the app, the notch, and the self-test | MVP |
| `NotchActivity` timers act out rehearsal | No real runs to show | The notch subscribes to **run events** (step started, finished, blocked) from RunEngine | MVP |
| `SelfTest` compiled into the app | Only the Command Line Tools are available, so there's no separate test target | A test target or test executable in the package; the app ships without test code | Before public beta |
| `PrototypePage`, "sample" names, hard-coded strings | Prototype vocabulary | Product names and a strings table (localization after the MVP) | Before public beta |
| Static site with its own build script | Pre-launch pages and a waitlist | Stays static. Add docs, a changelog, and download pages when a build ships | With the first build |

## Target architecture

```
apps/mac
├── Core            Pure Swift, no UI, fully testable
│   ├── Models      SkillDefinition, Run, Step, Receipt (status + evidence), Rule
│   ├── ReportEngine
│   ├── RunEngine   executes steps; read-only mode for rehearsal; emits run events
│   └── Rules       evaluates notes/rules against run state
├── Capture         screen video + action log (only while teaching, visible indicator, no passwords)
├── Learning        action log + key frames + notes → SkillDefinition, reviewed by the person
├── Executors       connector → AppleScript → Accessibility actions → keyboard; never the mouse
├── Connectors      Google Sheets (read-only first), Docs/Drive/Gmail, then Microsoft 365, then MCP
├── Store           AccountStore (Supabase, source of truth) and LocalStore (cache, Sample mode)
├── AI              Understudy Cloud (server-side proxy), your own key (Keychain), Apple on-device
└── App             SwiftUI/AppKit: main window, notch, menu bar, settings
supabase            auth, tables + RLS, Edge Functions (ai-proxy, connector token exchange), billing
apps/web            static site
qa                  self-test, evals, CI, reports
```

Rules that shape the architecture:
- **Core has no UI and no network.** Everything product-critical is testable with standalone checks, like `ReportEngine` today.
- **Rehearsal is read-only by construction.** RunEngine refuses write steps in rehearsal mode, and connectors receive read-only credentials. It isn't left to good behavior.
- **Status and evidence are separate types.** A step can be Done but Not verifiable, and the receipt shows both.
- **Understudy's secrets never reach the Mac.** Its provider keys live in Edge Functions, and connector refresh tokens are held server-side, encrypted, per user. A person's own API key stays in their Keychain.
- **Understudy executes; models advise.** Models learn the skill and write judgment steps. Numbers are computed in `Decimal`, never by a model.
- **Every stored format has a version,** and every change ships with a migration and a check.

## Quality system

The QA system already in place is what keeps this plan honest as it grows.

- `qa/run.py` is the release gate. It runs the checks, the simulated-user self-test, the website QA, and the held-out evals, and it draws the coverage graph and the trend.
- Each new feature adds its nodes and edges to `qa/flows.json`, invariants to `SelfTest`, and cases to the checks.
- The held-out eval set grows with each new workflow. The rule stays: only harnesses read `data/evaluation/`.
- CI runs the full matrix on every pull request, across the macOS versions a person might have.
- **Memory in long sessions.** The self-test found no leaks in Understudy's code: `leaks` shows only about 20 KB in Apple's LinkServices, and that doesn't grow. Two things still grow slowly, and both come from the frameworks. AppKit keeps a small key-value dependency (about 160 bytes) each time SwiftUI inserts a native control, which is a few KB per day for normal use. The Receipts picker also lists every receipt, so it grows with the receipt history. Recheck both in long sessions, and paginate receipts once people have months of history.

## Roadmap

Build one real vertical slice first (record the weekly update → learned skill → blind rehearsal → receipt), then widen. Every phase ends with the QA gate green, CI green on every macOS version, and a review.

0. **Foundations (done):** `UnderstudyCore`, `SkillDefinition` v1, `AccountStore`/`LocalStore`, `AppEnvironment`, a stable self-signed identity so macOS keeps permissions across builds, Apache 2.0.
1. **Record for real:** Screen Recording and Accessibility permissions, asked when recording starts; screen video plus action log; the notch shows real actions; recordings stay on the Mac.
2. **AI in three modes:** the `ai-proxy` Edge Function with per-user usage, your own key in the Keychain, and Apple on-device (text only).
3. **Learn:** key frames + action log + notes → a validated `SkillDefinition`; a real skill review; "Simulated" labels removed where things are real.
4. **Rehearse and run:** `RunEngine` with executors; rehearsal refuses every non-read step; send and delete wait for approval; receipts with read-back evidence; an end-to-end eval from recording to held-out weeks.
5. **Cloud connectors:** Google (Sheets, Drive, Docs, Gmail) through server-side token exchange, then Microsoft 365.
6. **Open-source release:** DMG on GitHub Releases, first-launch guidance for the unsigned-developer warning, the website updated to what works, and billing for Understudy Cloud.

**After the MVP:** scheduled runs, scoped corrections, memory with sources, more connectors and MCP, then Team (shared library, approvals, Cover for me).

## Decisions the plan needs from the owner

- **Apple Developer Program ($99/year):** skipped for now (owner decision). Without it: no notarization and no Sign in with Apple.
- **Where data lives by default:** local-first with optional sync, or account-first. Today it is account after sign-in, with Sample mode before.
- **AI costs per run,** measured once the proxy exists, before usage limits are set for each plan.
