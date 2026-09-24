# Understudy

**Show it once. Then hand it off.**

Understudy is a Mac companion that lives in the MacBook notch. You do a recurring task once while it watches. It turns the demonstration into a **skill**, proves it learned by **rehearsing** on past examples it hasn't seen (read-only, so nothing live changes), and then runs the task for you. Every run ends with a **receipt** that keeps what it did (status) separate from how it checked (evidence).

Understudy is its own runtime. It runs each step through connectors to your apps and calls an AI model only for the steps that need judgment. It is not a plug-in or a skill exporter for another AI app.

The first workflow is the **weekly client update** for agencies and consultancies: campaign figures from a sheet → a report in your template → a tracker row → a client email waiting for your approval.

## Status

In development, not yet available to users.

| Area | State |
|---|---|
| Mac app | Clickable prototype: main window, a live notch strip, accounts, and Sample mode. Watching, learning, and rehearsal are **simulated**. |
| Report engine | Real `Decimal` math that follows the report spec and matches the sample weeks exactly. Not wired into the app yet. |
| Accounts | Supabase project live, with email sign-in. Google and Apple sign-in are not configured yet. |
| Website | Pre-launch site with an early-access waitlist, deployed on Vercel. |
| Capture and learning | Research phase; the capture experiment is paused. |

Capabilities are only described as working once they can be demonstrated in the real app.

## Repository layout

```
understudy/
├── apps/
│   ├── mac/                 Native macOS app (SwiftUI + AppKit, Swift package)
│   │   ├── Sources/Understudy/
│   │   ├── Tests/           Standalone checks, compiled with swiftc
│   │   ├── Resources/       App icon
│   │   └── scripts/         bundle.sh (build the .app), make-icon.swift
│   └── web/                 Pre-launch website (static, no dependencies)
│       ├── src/             Layout, pages, assets
│       ├── build.mjs        Builds src/ into dist/
│       └── vercel.json      Hosting config and security headers
├── supabase/migrations/     Database schema, row-level security, waitlist functions
├── data/
│   ├── fixtures/teaching/   Synthetic sample agency data (weeks 0–3)
│   ├── evaluation/holdout/  Held-out test weeks (4–7), for test harnesses only
│   └── templates/           The weekly report template
├── docs/
│   ├── product/             Product context, prototype scope, report spec
│   ├── app/                 How each part of the Mac app works
│   ├── research/            Capture experiment and interview kit
│   └── setup/               Accounts and services setup
├── qa/                      Self-test runner, flow graph, evals, QA report
├── tools/ax-capture/        Accessibility capture recorder (experiment)
├── AGENTS.md                Project guide for coding agents
└── CHANGELOG.md
```

## Getting started

### Mac app

Building requires Swift 6.1 or later (Xcode 16.3+ or its Command Line Tools), because supabase-swift needs it. The built app runs on macOS 14 or later.

```bash
apps/mac/scripts/bundle.sh
open apps/mac/build/Understudy.app
```

Without a server config, the app runs in Sample mode. To connect accounts, copy `apps/mac/config.example.json` to `apps/mac/config.local.json` (git-ignored), fill in the Supabase URL and publishable key, and rebuild. See [docs/setup/accounts.md](docs/setup/accounts.md).

To play the website's hero sequence in the real notch, run `open apps/mac/build/Understudy.app --args --notch-demo`.

### Website

```bash
cd apps/web
node build.mjs
npx serve dist
```

### Database

Apply the files in `supabase/migrations/` in order, in the Supabase SQL editor.

### Checks

Each check is a small executable. For example:

```bash
swiftc apps/mac/Sources/Understudy/ReportEngine.swift apps/mac/Tests/ReportChecks.swift -o /tmp/report-checks && /tmp/report-checks
```

The full list is in [AGENTS.md](AGENTS.md#build-and-test), and every pull request runs them automatically.

## Documentation

- [Product context](docs/product/product-context.md): what Understudy is, the decisions behind it, and open questions
- [Prototype scope](docs/product/prototype-1.md) and the [report spec](docs/product/report-spec.md)
- [Mac app guide](docs/app/interface-prototype.md), [Watch](docs/app/watch-slice.md), [keyboard shortcuts](docs/app/keyboard-shortcuts.md), [report engine](docs/app/report-engine.md)
- [Long-term plan](docs/product/long-term-plan.md): what is temporary today, the target architecture, and the roadmap
- [Accounts setup](docs/setup/accounts.md)
- QA: `python3 qa/run.py` runs every suite and writes `qa/out/report.html` (see [AGENTS.md](AGENTS.md#qa-and-evals))

## Contributing

Work happens on branches and lands through pull requests. The workflow and project rules are in [AGENTS.md](AGENTS.md).

## License

[Apache License 2.0](LICENSE). The repository is private until its first public release.
