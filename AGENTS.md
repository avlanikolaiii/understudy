# AGENTS.md

Project guide for coding agents working on Understudy (Codex, Claude Code, and others). `CLAUDE.md` imports this file, so this is the single source of truth. Read it before making changes.

## Project

Understudy is a macOS companion that lives in the MacBook notch, with a menu bar and main-window fallback. A person demonstrates a recurring task once. Understudy turns it into a **skill**, rehearses it **blind and read-only** on past examples, then runs it and produces a **receipt** that keeps execution status separate from verification evidence.

- **Tagline:** "Show it once. Then hand it off."
- **Runtime:** Understudy runs steps itself through connectors and calls AI models (Claude Opus 5.5, GPT-5.6 Sol) only for steps that need judgment. It is not a plug-in or skill exporter for ChatGPT or Claude.
- **First workflow:** the weekly client update (sheet figures → report from a template → tracker row → email draft awaiting approval).
- **Initial customer hypothesis:** agencies and consultancies. This is a hypothesis, not validated demand.
- **Status:** in development. Watch records real demonstrations (screen video and an action log, kept on the Mac). Learning and rehearsal are still simulated. The report engine is real but not wired into the app yet.

## Repository layout

| Path | Contents |
|---|---|
| `apps/mac/` | macOS app: Swift package, SwiftUI + AppKit. `Sources/UnderstudyCore/` is pure Swift (models, engines; no UI, no network); `Sources/Understudy/` is the app. Standalone checks in `Tests/`, build scripts in `scripts/`. |
| `apps/web/` | Pre-launch website: static pages built by `build.mjs` into `dist/`, deployed on Vercel. |
| `supabase/migrations/` | Database schema, row-level security, and waitlist functions, numbered in order. |
| `data/fixtures/teaching/` | Synthetic sample agency data (weeks 0–3). Safe to read. |
| `data/evaluation/holdout/` | Held-out test weeks (4–7). **Test harnesses only.** |
| `data/templates/` | The weekly report template. |
| `docs/` | `product/` (context, scope, report spec), `app/` (Mac app behavior), `research/` (capture experiment, interview kit), `setup/` (accounts and services). |
| `tools/ax-capture/` | Accessibility capture recorder for the paused capture experiment. |

## Architecture

- **Main window** (`MainWindowView`, `WorkspaceController`): Home, Teach a skill, Skills, Receipts, and Account. Sign-in happens here only.
- **Notch** (`NotchController`, `NotchLiveView`, `NotchActivity`): a live strip styled after the website hero. It shows the states Watching → New skill → Rehearsing (read-only) → Receipt. It never takes keyboard input.
- **Skills** (`UnderstudyCore/SkillDefinition.swift`): a skill is a procedure Understudy runs itself, never an export for another AI app. Version 1 holds the trigger, inputs, steps (each with its executor, target, effect, and evidence), rules, and output, and is stored in `skills.definition`. Older formats decode into the current one; newer ones are refused.
- **Data** (`SkillLibrary.swift`, `AccountStore.swift`, `Library.swift`): one list of skills and receipts. The account (`AccountStore`, Supabase) is the source of truth after sign-in. `LocalStore` is the versioned file on this Mac (`~/Library/Application Support/Understudy/interface-prototype.json`) for Sample mode before sign-in. Async work from a previous owner is dropped when the user signs in or out.
- **Composition** (`AppEnvironment.swift`): the app's objects are created once here and shared by the main window, the notch, the menus, and the self-test.
- **Auth** (`AppModel`): Supabase Auth with Google, Apple, and email link, using PKCE and the redirect `understudy://auth-callback`.
- **Report engine** (`UnderstudyCore/ReportEngine.swift`): pure Foundation, using `Decimal`, and following `docs/product/report-spec.md`.
- **Watch** (`WatchSession.swift`, `Capture/`): records a demonstration through a replaceable `CaptureSource`: `ScreenCapture` (ScreenCaptureKit video through macOS's picker, plus an Accessibility action log) on a Mac, `ScriptedCapture` in tests. Recordings are folders in `~/Library/Application Support/Understudy/recordings/`. See `docs/app/watch.md`.
- **Shortcut** (`KeyboardShortcut.swift`): a Carbon hot key (default ⌥ Space), remappable, that needs no Accessibility permission. It starts Watch; pressing it again stops Watch and opens the review.

## Build and test

The toolchain is the Command Line Tools only (no Xcode). Building needs Swift 6.1 or later (supabase-swift requires it); the built app runs on macOS 14 or later. Run commands from the repository root.

| Task | Command |
|---|---|
| Build the Mac app | `apps/mac/scripts/bundle.sh` → `apps/mac/build/Understudy.app` |
| Build the website | `cd apps/web && node build.mjs` → `apps/web/dist/` |
| Checks and held-out eval | `python3 qa/run.py --skip-build --only checks,eval-holdout` (builds `UnderstudyCore` as a module and links each check to it) |
| Stable signing identity | `apps/mac/scripts/make-signing-identity.sh`, once per Mac. `bundle.sh` then signs with it so macOS keeps the app's privacy permissions across builds. |

Continuous integration builds the app once (macos-15, Swift 6.1), runs the checks and held-out eval, and then installs that same bundle on fresh macos-14, macos-15, and macos-26 runners for simulated users and a real first launch, on every pull request (`.github/workflows/ci.yml`).

## QA and evals

`python3 qa/run.py` is the release gate. It uses the standard library only; run it from the repository root on a Mac.

- **Checks:** the standalone checks in `apps/mac/Tests/` (the `CHECKS` table in `qa/run.py`).
- **Self-test:** `Understudy --self-test=SESSIONS,SEED`. It simulates people using the real app objects: random walks over `qa/flows.json` that use only controls on screen and enabled. It checks documented rules after every step and renders every screen to PNG. It uses a temporary library and no server, so your data is never touched.
- **Website:** `apps/web/qa.mjs` checks every built page.
- **Held-out eval:** `qa/eval-holdout.swift`. It is the only reader of `data/evaluation/`, and it prints scores only.
- **Agent-run suites:**
  - `qa/browser-sessions.js`: simulated visitors against a fake Supabase.
  - `qa/db-waitlist.sql`: a mass waitlist test, rolled back.
  - Save their JSON to `qa/out/browser.json` and `qa/out/db.json`, with `"fingerprint"` from `python3 qa/run.py --fingerprint browser|db`. A result whose sources changed since it ran is stale and fails the gate.
- **Output:** `qa/out/report.html` shows a coverage graph of every flow node, the trend across runs (`qa/history.jsonl`), actions taken, and eval scores.

**A finding counts only if all three hold:** it reproduces twice from its seed or steps; it points to a line of code; and it breaks documented behavior, not taste. Screenshot or timing artifacts are verified against the real screen before anything is called a bug.

**Done when:** three consecutive clean iterations, every automated node covered, and CI green on every macOS version.

## Rules

- **Honest labels.** Simulated behavior is labeled "Simulated" or "Concept demonstration" in the UI, the docs, and the website. A capability is described as working only when it can be demonstrated in the real app.
- **Held-out data.** App code, learning code, and agents during development never open, read, list, or grep `data/evaluation/`. Use `data/fixtures/teaching/`.
- **Read-only rehearsal.** Rehearsal never writes to any connected account. It writes only to local output.
- **Report math.** Numbers follow `docs/product/report-spec.md` exactly: `Decimal`, half-up rounding at display time, and missing data is never estimated. If a fixture disagrees with the spec, stop and report it; the spec wins.
- **Secrets.** Secrets (the Supabase secret key, Google client secret, Apple `.p8` key, Anthropic key, Vercel tokens) never enter the repository, the app bundle, or the website. `apps/mac/config.local.json` and `.env*` files are git-ignored. The Supabase publishable key is public by design.
- **Permissions and outreach.** Ask the human before sending outreach, creating files in the human's Google Drive, requesting new macOS permissions, or publishing public content.
- **SwiftUI macros.** The macro plugins are unavailable: don't use `@State`, `@Observable`, or `#Preview`. Keep view state in `ObservableObject` classes with `@Published` properties.
- **Deployment target.** The product requires macOS 26 or later; the package targets macOS 14 so it builds with the current toolchain.

## Workflow

### Branches and commits
- Branch from `main` as `<type>/<short-description>`, for example `feat/skill-review` or `fix/notch-resize`.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `feat`, `fix`, `refactor`, `docs`, `test`, `ci`, `chore`.
- The subject is imperative and at most 72 characters. The body explains why.
- Keep each commit buildable and focused on one change.
- Add user-visible changes to `CHANGELOG.md` under **Unreleased**.

### Pull requests
- Every change reaches `main` through a pull request. Nothing is pushed to `main` directly.
- Open a **draft** pull request early. It signals which files are in progress, and no other agent edits them until it merges or closes.
- Fill in `.github/pull_request_template.md`: what changed, why, how it was verified, and what wasn't verified.
- CI must pass before merge.
- Another agent reviews:
  - Claude Code asks Codex with `codex exec review --base main`.
  - Codex asks Claude Code, or leaves the review to the human.
- The human approves the merge. Merge with **Rebase and merge** to keep the commit history clean.

### Tools
- The Codex CLI ships inside the ChatGPT app at `/Applications/ChatGPT.app/Contents/Resources/codex`.
- The GitHub CLI is `/opt/homebrew/bin/gh`, signed in to the repository owner's account.
- Code-review commands and PR commands are listed under Pull requests above.
- A `codex exec` sandbox cannot write `.git`. Work produced there is committed by another agent or the human, crediting Codex with `Co-Authored-By: Codex <noreply@openai.com>`.

## Services

| Service | Details |
|---|---|
| GitHub | `avlanikolaiii/understudy` (private until the human decides to publish it; Apache 2.0). Default branch `main`. |
| Vercel | Project `understudy` (team `nicolas-leons-projects`), root directory `apps/web`, live at https://understudy-nine-dusky.vercel.app. Deploy with `cd apps/web && npx vercel deploy --prod`. Git integration requires the Vercel GitHub app on the repository. |
| Supabase | Project `idwgaqnpheittqtllhzl` (São Paulo). Email sign-in is enabled; the redirect `understudy://auth-callback` is allowed. Migrations are applied in order, by hand, in the SQL editor. Waitlist signups are in the `waitlist` table. |

## Product decisions

Reopen these only with the human's approval.

- **Pricing (provisional):** Free $0 (up to 5 skills), Pro $15/month, Team $30/person/month (includes "Cover for me").
- **Execution:** Understudy runs every skill itself, with models called from inside the app. Skills are never exported to, or run inside, Claude, ChatGPT, or Gemini.
- **Capture:** Watch records a video of the screen (ScreenCaptureKit) and a log of actions, including which button was clicked (Accessibility), only while the person teaches. The recording stays on the Mac; learning sends the action log and key frames to the chosen AI.
- **Running without the mouse:** steps run through, in order of preference, a connector's API, the app's scripting, Accessibility actions, then the keyboard. A step that would need the mouse is shown to the person as unsupported.
- **AI:** three modes. Understudy Cloud (default: Claude, ChatGPT, and Gemini through a server-side proxy, paid by a monthly fee), your own API key (stored in the Keychain), and Apple's on-device model.
- **Distribution:** open source (Apache 2.0). A self-signed DMG on GitHub Releases, without the Apple Developer Program or notarization for now, so the first open shows macOS's downloaded-from-the-internet warning. No Homebrew and no Mac App Store.
- **The notch** is the product's signature and a live status strip. Sign-in, skills, and receipts live in the main window.
- **Data:** skills, receipts, and connections live in each user's cloud account; the copy on the Mac is a cache and the labeled Sample mode before sign-in.
- **Website:** one English pre-launch site. The home page is the hero only; each menu item is its own page. There are no download links until a working build is released.
- **Corrections:** a correction applies to the current workflow only in the first prototype.

## Roadmap

The phases, what is temporary today, and the target architecture are in `docs/product/long-term-plan.md`. Build one real vertical slice first (record the weekly update → learned skill → blind rehearsal → receipt), then widen.

0. **Foundations:** `UnderstudyCore`, `SkillDefinition` v1, `AccountStore`/`LocalStore`, `AppEnvironment`, a stable signing identity, Apache 2.0.
1. **Record for real:** screen video and action log replace the simulated Watch.
2. **AI in three modes:** Understudy Cloud proxy, your own key, Apple on-device.
3. **Learn:** recording + notes → `SkillDefinition`, with a real skill review.
4. **Rehearse and run:** `RunEngine` and executors replace `SampleEngine` and the notch timers; receipts with read-back evidence.
5. **Cloud connectors:** Google (Sheets, Drive, Docs, Gmail), then Microsoft 365, with tokens held server-side.
6. **Open-source release:** DMG on GitHub Releases, first-launch guidance, website updated to what works, billing for Understudy Cloud.

The capture experiment (`tools/ax-capture`, `docs/research/capture-experiment.md`) is the starting point for phase 1.
