# Long-term plan

How Understudy grows from today's prototype to a product. It separates the code that exists
to show the idea now from the architecture that has to last, and it orders the work.

## The MVP

The MVP is the launchable version of [Prototype 1](prototype-1.md): one workflow, the weekly client update, on a person's own Mac.

- A signed, notarized download that opens without warnings on a clean Mac.
- A first run on sample data with no accounts: rehearsal and a receipt in under 5 minutes (T6).
- **Teach:** one real demonstration of the update becomes a skill with no hand edits (T1).
- **Rehearse:** read-only, blind, on held-out weeks, with exact numbers (T2, T3). A missing figure is blocked, never guessed (T4).
- **Run:** one Google Sheet in, one Markdown report out, and a receipt whose evidence is a read-back of the output (T5).
- **Account:** sign-in and a waitlist-to-customer path.

Everything else in the roadmap below comes after the MVP.

## What is temporary today, and what replaces it

| Today | Why it exists | Replaced by | When |
|---|---|---|---|
| `WatchSession`: a fixed 5-step replay | Shows the Watch experience before capture works | **Capture:** an Accessibility event log (from `tools/ax-capture`) of apps, fields, and values | MVP |
| `SampleEngine`: fixed report text | Shows rehearsal and receipts on sample data | **RunEngine** driving `ReportEngine` on real inputs | MVP |
| `Skill` = name, client, notes | Enough to save and list skills | **SkillDefinition v1:** trigger, inputs, ordered steps, rules, and `schemaVersion`, stored in `skills.definition` | MVP |
| Notes stored, never applied | No learning yet | **Learning:** event log + notes → SkillDefinition, through the AI proxy, reviewed in Skill review | MVP |
| `interface-prototype.json` | Sample mode storage | **Store** protocol with versioned files and migrations (local), and the same protocol over Supabase (account) | MVP |
| `SkillLibrary` calls Supabase directly | Fastest path to accounts | `LocalStore` and `AccountStore` behind one protocol; sync is a separate component | MVP |
| `AppDelegate` builds every object | A single-window prototype | An `AppEnvironment` composition root that the app, the notch, and tests all use | MVP |
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
├── Capture         Accessibility event log (opt-in, visible indicator, no passwords)
├── Learning        event log + notes → SkillDefinition (via AI proxy), with a diff for review
├── Connectors      protocol + Google Sheets (read-only first), then Docs/Drive/Gmail, then MCP
├── Store           local files (versioned) and Supabase account, behind one protocol; sync
├── AIClient        talks only to the Supabase Edge Function; never holds provider keys
└── App             SwiftUI/AppKit: main window, notch, menu bar, settings
supabase            auth, tables + RLS, Edge Functions (ai-proxy, Google token exchange), later billing
apps/web            static site
qa                  self-test, evals, CI, reports
```

Rules that shape the architecture:
- **Core has no UI and no network.** Everything product-critical is testable with standalone checks, like `ReportEngine` today.
- **Rehearsal is read-only by construction.** RunEngine refuses write steps in rehearsal mode, and connectors receive read-only credentials. It isn't left to good behavior.
- **Status and evidence are separate types.** A step can be Done but Not verifiable, and the receipt shows both.
- **Secrets never reach the Mac.** Provider keys live in Edge Functions. Google tokens are stored in the Keychain with the narrowest scopes.
- **Every stored format has a version,** and every change ships with a migration and a check.

## Quality system

The QA system already in place is what keeps this plan honest as it grows.

- `qa/run.py` is the release gate. It runs the checks, the simulated-user self-test, the website QA, and the held-out evals, and it draws the coverage graph and the trend.
- Each new feature adds its nodes and edges to `qa/flows.json`, invariants to `SelfTest`, and cases to the checks.
- The held-out eval set grows with each new workflow. The rule stays: only harnesses read `data/evaluation/`.
- CI runs the full matrix on every pull request, across the macOS versions a person might have.
- **Memory in long sessions.** The self-test found no leaks in Understudy's code: `leaks` shows only about 20 KB in Apple's LinkServices, and that doesn't grow. Two things still grow slowly, and both come from the frameworks. AppKit keeps a small key-value dependency (about 160 bytes) each time SwiftUI inserts a native control, which is a few KB per day for normal use. The Receipts picker also lists every receipt, so it grows with the receipt history. Recheck both in long sessions, and paginate receipts once people have months of history.

## Roadmap

1. **MVP (launch).** Capture, Learning, and Skill review, then RunEngine with a real rehearsal on held-out weeks, the Google Sheets read-only connector, and the AI proxy. Also Developer ID signing, notarization, the DMG, and Sparkle updates, plus Google sign-in and custom SMTP for email.
2. **After launch.** Tracker updates and the client email draft (write steps, always approved first); scheduled runs; scoped corrections (this client, everywhere); and memory with sources.
3. **Growth.** More connectors and MCP, then Team: a shared skill library, approvals from Slack or Teams, and Cover for me. Finally billing and plan limits beyond the free tier.

## Decisions the plan needs from the owner

- **Apple Developer Program ($99/year):** required for notarized downloads and Sign in with Apple.
- **Where data lives by default:** local-first with optional sync, or account-first. Today it is account after sign-in, with Sample mode before.
- **AI costs per run,** measured once the proxy exists, before usage limits are set for each plan.
