# AGENTS.md: Understudy (handoff for coding agents)

Read this file first. It's the project's standing context and rules. Handed over from Claude Code on 2026-09-23.

## What Understudy is

A Mac companion that lives in the MacBook notch (with a menu bar fallback). You show it a recurring task once. It writes a **skill**, proves it learned by **rehearsing** on past examples it hasn't seen (read-only), then runs the task and gives you a **receipt** that keeps *what it did* (status) separate from *how it checked* (evidence). Understudy is its own runtime: it runs the steps itself, through connectors. AI models (Claude Opus 5.5 or GPT-5.6 Sol) are only called for steps that need judgment. It is **not** a plug-in or skill exporter for ChatGPT or Claude.

- Tagline: "Show it once. Then hand it off."
- First customer hypothesis: agencies and consultancies. Flagship workflow: the **weekly client update** (Google Sheet data → report from a template → tracker row → email draft waiting for approval).
- Status: **product concept**. Nothing in the product works for users yet.

## Current priority: the clickable app prototype (`app/`)

The capture experiments and customer validation are **paused**. Keep their files, but don't extend them unless asked.

### Done (slice 1, commit `8aac6ad`)
- A native macOS app (SwiftUI + AppKit, Swift package) in `app/`. Build it with `app/scripts/bundle.sh`, which produces `app/build/Understudy.app`.
- `NotchController.swift`: a borderless, non-activating panel over the notch. Click it or press ⌥ Space (a Carbon hot key, so no Accessibility access is needed) to expand. On Macs without a notch it drops down below the menu bar. There's also a menu bar item.
- `AppModel.swift`: Supabase Auth with **Google, Apple, and email link** sign-in (`supabase-swift` 2.55.x, PKCE, deep link `understudy://auth-callback`). After sign-in it loads the user's skills and adds one labeled sample skill.
- `PanelViews.swift`: the sign-in, home, and "not configured" views.
- `supabase/migrations/0001_accounts_and_skills.sql`: `profiles`, `skills`, and `receipts`, with row-level security on every table and a server-side free-plan limit (5 non-sample skills).
- `docs/setup/accounts.md`: Supabase, Google OAuth, and Apple setup (the human does this: it involves accounts and secrets).

### Waiting on the human
Create the Supabase project, the Google OAuth client, and the Apple Services ID and key, then create `app/config.local.json` (see `app/config.example.json`). Until then, the app shows "Not connected to a server yet".

### Done after handoff (slice 2)
- **Watch, simulated:** a five-step predefined replay in the notch, pulsing indicator, timer, temporary rules, Stop, Replay, and Done. Available without sign-in. The configured global shortcut (default Option-Space) stops an active replay.
- Release bundle, session checks, and rendered-view checks passed. Full notch/shortcut interaction and the no-notch fallback are not yet verified end to end. See `docs/watch-slice.md`.
- `docs/product-context.md` captures the original Claude conversations, product artifacts, superseded ideas, and unresolved design gaps. Read it before changing the product direction.

### Shortcut settings
- The notch gear and menu-bar **Keyboard Shortcut…** open a native recorder. The shortcut persists across launches, supports restoring Option-Space, and retains the old binding when a remap fails. See `docs/keyboard-shortcuts.md`.

### Main app teaching and native workspace
- The workspace and notch share a single simulated Watch session. Start from **Teach a skill** in the main app, stop/replay in either surface, and carry notes into local sample-skill review.
- The main window uses a native sidebar and toolbar, system appearance, Dock entry, and standard menus. Command-N opens teaching; Command-comma opens shortcut settings.
- The existing local sample skill/rehearsal/export prototype is retained. It does not replace the account-backed slices below. See `docs/interface-prototype.md`.

### Next slices, in order
1. **Skill review**: the learned skill shown in plain words (trigger, steps, inputs, rules), with rules editable. The skill is prepared in advance (*simulated* learning) and saved to `skills.definition` (jsonb).
2. **Rehearse**: two past teaching weeks, a read-only badge, its version and what was sent side by side, matches and differences, then Hand off / Rehearse again / Correct (a correction applies to this workflow only).
3. **Run and receipt**: compute the report from the sheet using `docs/report-spec.md`, write the Markdown file to a local git-ignored folder, read it back as evidence, and save the receipt to `receipts`. Include a toggle for a week with **ad spend missing**: the report stays an incomplete draft, the tracker says it needs input, and the email is held back.
4. **Google Sheets connector** (read-only scope; rehearsal must use a read-only token).
5. **AI proxy**: a Supabase Edge Function that holds the Anthropic key server-side and is used for summary and highlight text. Never put the key in the app.

## Rules you must follow

- **Honest labels.** Never present simulated behavior as working. Label it "Simulated" or "Concept demonstration" in the UI and the docs. Nothing is "working" without a demo you can reproduce.
- **Held-out data.** `evaluation/holdout/` contains unseen test weeks. App and learning code must **never** read it. Only a test harness may. Use `fixtures/teaching/` for development and demos.
- **Read-only rehearsal** across *every* connected account. Write only to a local output folder.
- **Numbers** follow `docs/report-spec.md` exactly: decimal half-up rounding, and missing data is never estimated.
- **Secrets** (the Google client secret, Apple `.p8` key, Anthropic key, Supabase service key) never go into the repo or the app. `.gitignore` covers `config.local.json`, `runs/`, `client-examples/`, and the key files.
- **Don't** send outreach, create files in the user's Google Drive, or request new macOS permissions without asking the human first.
- **Toolchain gotcha:** this Mac has the Command Line Tools, not Xcode. The SwiftUI macro plugins are missing, so **don't use `@State`, `@Observable`, or `#Preview`**. Keep view state in `ObservableObject` classes with `@Published`, as the existing code does. Build with `swift build` or `app/scripts/bundle.sh`.
- The product requires macOS 26+; the package targets macOS 14 so it builds easily.

## Decisions already made (don't reopen without asking)

- Pricing (provisional): Free $0 (up to 5 skills), Pro $15/month, Team $30/person/month (includes "Cover for me").
- Distribution: a signed and notarized DMG, plus a zip on GitHub Releases for Sparkle updates. No Homebrew, and not the Mac App Store.
- One English landing page. It's a claude.ai artifact, and it isn't in this repo.

## Where things are

| Path | What |
|---|---|
| `app/` | The macOS app (current work) |
| `supabase/migrations/` | Database schema and security |
| `docs/setup/accounts.md` | Account setup for the human |
| `docs/prototype-1.md`, `docs/report-spec.md` | Prototype scope and the exact report math |
| `docs/capture-experiment.md`, `tools/ax-capture/` | Capture experiment (paused) and recorder |
| `docs/validation/` | Interview kit in English and Spanish (paused, nothing sent) |
| `fixtures/teaching/`, `templates/` | Sample agency data and the report template |
| `evaluation/holdout/` | **Don't read.** Held-out test weeks |

## Working style

Commit in small steps with clear messages. Before saying something works, build it and check it. Say plainly what you verified and what you didn't.
