# AGENTS.md

Project guide for coding agents working on Understudy (Codex, Claude Code, and others). `CLAUDE.md` imports this file, so this is the single source of truth. Read it before making changes.

## Project

Understudy is a macOS companion that lives in the MacBook notch, with a menu bar and main-window fallback. A person demonstrates a recurring task once. Understudy turns it into a **skill**, rehearses it **blind and read-only** on past examples, then runs it and produces a **receipt** that keeps execution status separate from verification evidence.

- **Tagline:** "Show it once. Then hand it off."
- **Runtime:** Understudy runs steps itself through connectors and calls AI models (Claude Opus 5.5, GPT-5.6 Sol) only for steps that need judgment. It is not a plug-in or skill exporter for ChatGPT or Claude.
- **First workflow:** the weekly client update (sheet figures → report from a template → tracker row → email draft awaiting approval).
- **Initial customer hypothesis:** agencies and consultancies. This is a hypothesis, not validated demand.
- **Status:** in development. The Mac app is a clickable prototype; watching, learning, and rehearsal are simulated. The report engine is real but not wired into the app yet.

## Repository layout

| Path | Contents |
|---|---|
| `apps/mac/` | macOS app: Swift package, SwiftUI + AppKit. Sources in `Sources/Understudy/`, standalone checks in `Tests/`, build scripts in `scripts/`. |
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
- **Data** (`Library.swift`, `SkillLibrary.swift`): one list of skills and receipts. **Sample mode** stores data on the Mac (`~/Library/Application Support/Understudy/interface-prototype.json`) before sign-in, and the Supabase account stores it after sign-in. Async work from a previous owner is dropped when the user signs in or out.
- **Auth** (`AppModel`): Supabase Auth with Google, Apple, and email link, using PKCE and the redirect `understudy://auth-callback`.
- **Report engine** (`ReportEngine.swift`): pure Foundation, using `Decimal`, and following `docs/product/report-spec.md`.
- **Shortcut** (`KeyboardShortcut.swift`): a Carbon hot key (default ⌥ Space), remappable, that needs no Accessibility permission. It starts Watch; pressing it again stops Watch and opens the review.

## Build and test

The toolchain is the Command Line Tools only (no Xcode). Run commands from the repository root.

| Task | Command |
|---|---|
| Build the Mac app | `apps/mac/scripts/bundle.sh` → `apps/mac/build/Understudy.app` |
| Build the website | `cd apps/web && node build.mjs` → `apps/web/dist/` |
| Report checks | `swiftc apps/mac/Sources/Understudy/ReportEngine.swift apps/mac/Tests/ReportChecks.swift -o /tmp/c && /tmp/c` |
| Library checks | `swiftc apps/mac/Sources/Understudy/Library.swift apps/mac/Tests/PrototypeChecks.swift -o /tmp/c && /tmp/c` |
| Watch checks | `swiftc apps/mac/Sources/Understudy/WatchSession.swift apps/mac/Tests/WatchChecks.swift -o /tmp/c && /tmp/c` |
| Workspace checks | `swiftc apps/mac/Sources/Understudy/{Library,WatchSession,WorkspaceState}.swift apps/mac/Tests/WorkspaceChecks.swift -o /tmp/c && /tmp/c` |
| Notch checks | `swiftc -parse-as-library apps/mac/Sources/Understudy/{Library,WatchSession,WorkspaceState,NotchActivity}.swift apps/mac/Tests/NotchChecks.swift -o /tmp/c && /tmp/c` |
| Shortcut checks | `swiftc apps/mac/Sources/Understudy/KeyboardShortcut.swift apps/mac/Tests/ShortcutChecks.swift -o /tmp/c && /tmp/c` |

Continuous integration runs the same commands on every pull request (`.github/workflows/ci.yml`).

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
| GitHub | `avlanikolaiii/understudy` (private). Default branch `main`. |
| Vercel | Project `understudy` (team `nicolas-leons-projects`), root directory `apps/web`, live at https://understudy-nine-dusky.vercel.app. Deploy with `cd apps/web && npx vercel deploy --prod`. Git integration requires the Vercel GitHub app on the repository. |
| Supabase | Project `idwgaqnpheittqtllhzl` (São Paulo). Email sign-in is enabled; the redirect `understudy://auth-callback` is allowed. Migrations are applied in order, by hand, in the SQL editor. Waitlist signups are in the `waitlist` table. |

## Product decisions

Reopen these only with the human's approval.

- **Pricing (provisional):** Free $0 (up to 5 skills), Pro $15/month, Team $30/person/month (includes "Cover for me").
- **Distribution:** a signed, notarized DMG and a zip on GitHub Releases for Sparkle updates. No Homebrew and no Mac App Store.
- **The notch** is the product's signature and a live status strip. Sign-in, skills, and receipts live in the main window.
- **Data:** skills and receipts live in the user's account after sign-in, with a labeled local Sample mode before sign-in.
- **Website:** one English pre-launch site. The home page is the hero only; each menu item is its own page. There are no download links until a signed build exists.
- **Corrections:** a correction applies to the current workflow only in the first prototype.

## Roadmap

1. **Skill review:** show the learned skill in plain words (trigger, steps, inputs, rules), make rules editable, and save to `skills.definition`.
2. **Real rehearsal:** drive rehearsal with `ReportEngine` on the teaching weeks instead of fixed sample text, and compare against the sent reports.
3. **Run and receipt:** write the Markdown report to a local git-ignored folder, read it back as evidence, and save the receipt. When ad spend is missing, the report stays an incomplete draft and the email is held back.
4. **Google Sheets connector:** read-only scope, and rehearsal uses a read-only token.
5. **AI proxy:** a Supabase Edge Function that holds the Anthropic key server-side and writes the summary and highlight.
6. **Sign-in providers:** Google OAuth next. Apple requires the paid Apple Developer Program.

The capture experiment and customer validation are paused. Keep their files; don't extend them unless asked.
