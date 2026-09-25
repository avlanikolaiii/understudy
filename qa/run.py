#!/usr/bin/env python3
"""Runs every QA suite, measures coverage of qa/flows.json, and draws the report.

    python3 qa/run.py                       # 300 sessions × seeds 1,2,3
    python3 qa/run.py --sessions 1000 --seeds 1,2,3,4,5
    python3 qa/run.py --quick               # 40 sessions, one seed (a smoke run)
    python3 qa/run.py --skip-build --only self-test   # run a prebuilt app on this Mac (CI matrix)

Standard library only. Run from the repository root on a Mac (the self-test needs a window
server). Writes qa/out/ (git-ignored): run.json, report.html, screenshots. Appends one summary
line to qa/history.jsonl. Exits 1 if any automated suite fails.
"""
import argparse, datetime, hashlib, html, json, pathlib, subprocess, sys, time

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "qa" / "out"
APP = ROOT / "apps/mac/build/Understudy.app/Contents/MacOS/Understudy"
SRC = "apps/mac/Sources/Understudy"
CORE = ROOT / "apps/mac/Sources/UnderstudyCore"
CORE_OUT = OUT / "core"
# Every check links UnderstudyCore, built once as a module by build_core().
CORE_FLAGS = ["-parse-as-library", "-I", str(CORE_OUT), "-L", str(CORE_OUT), "-lUnderstudyCore"]
CHECKS = {  # name: (extra swiftc flags, app sources, test)
    "report":    ([], [], "ReportChecks"),
    "definition": ([], [], "SkillDefinitionChecks"),
    "steps":     ([], [], "StepsChecks"),
    "run":       ([], [], "RunChecks"),
    "trigger":   ([], [], "TriggerChecks"),
    "commands":  ([], [], "CommandChecks"),
    "library":   ([], ["Library"], "PrototypeChecks"),
    "watch":     ([], ["WatchSession"], "WatchChecks"),
    "workspace": ([], ["Library", "WatchSession", "WorkspaceState"], "WorkspaceChecks"),
    "notch":     ([], ["Library", "WatchSession", "WorkspaceState", "NotchActivity"], "NotchChecks"),
    "shortcut":  ([], ["KeyboardShortcut"], "ShortcutChecks"),
}


def sh(cmd, cwd=ROOT, timeout=3600):
    started = time.time()
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    return proc.returncode, proc.stdout + proc.stderr, round(time.time() - started, 1)


def build_core():
    """Compiles UnderstudyCore into a static library and module, as SwiftPM would."""
    CORE_OUT.mkdir(parents=True, exist_ok=True)
    return sh(["swiftc", "-emit-library", "-static", "-emit-module", "-parse-as-library", "-module-name", "UnderstudyCore",
               *sorted(str(f) for f in CORE.glob("*.swift")),
               "-emit-module-path", str(CORE_OUT / "UnderstudyCore.swiftmodule"), "-o", str(CORE_OUT / "libUnderstudyCore.a")])


def run_checks():
    code, log, _ = build_core()
    if code != 0:
        return {"suite": "checks", "passed": 0, "total": len(CHECKS),
                "checks": [{"name": "core", "ok": False, "seconds": 0, "passes": [], "error": log[-600:]}]}
    results = []
    for name, (flags, sources, test) in CHECKS.items():
        binary = OUT / f"check-{name}"
        code, log, secs = sh(["swiftc", *flags, *CORE_FLAGS, *[f"{SRC}/{s}.swift" for s in sources],
                              f"apps/mac/Tests/{test}.swift", "-o", str(binary)])
        if code == 0:
            code, log, run_secs = sh([str(binary)])
            secs += run_secs
        results.append({"name": name, "ok": code == 0, "seconds": secs,
                        "passes": [l for l in log.splitlines() if l.startswith("PASS")],
                        "error": "" if code == 0 else log[-600:]})
    return {"suite": "checks", "passed": sum(r["ok"] for r in results), "total": len(results), "checks": results}


def run_self_test(sessions, seeds):
    runs = []
    for seed in seeds:
        out = OUT / f"self-test-{seed}"
        (out / "self-test.json").unlink(missing_ok=True)
        code, log, secs = sh([str(APP), f"--self-test={sessions},{seed}", f"--self-test-out={out}"], timeout=7200)
        report = json.loads((out / "self-test.json").read_text()) if (out / "self-test.json").exists() else {}
        runs.append({"seed": seed, "ok": code == 0 and bool(report), "seconds": secs, "exit": code,
                     "steps": report.get("steps", 0), "failures": report.get("failures", [{"rule": "self-test.crashed", "detail": log[-400:]}]),
                     "nodes": report.get("nodes", {}), "edges": report.get("edges", {})})
    return {"suite": "self-test", "passed": sum(r["ok"] for r in runs), "total": len(runs), "sessions": sessions, "runs": runs}


def fresh_report(path, cmd, cwd=ROOT, suite=""):
    """Runs a suite that writes its own JSON report. The old report is deleted first, so a crash
    can never inherit a previous pass; a missing report is a failure."""
    path.unlink(missing_ok=True)
    code, log, _ = sh(cmd, cwd=cwd)
    if not path.exists():
        return {"suite": suite, "passed": 0, "total": 1, "checks": [], "weeks": [],
                "error": f"exit {code} without a report: {log[-400:]}"}
    report = json.loads(path.read_text())
    if code != 0 and report.get("passed") == report.get("total"):
        report["passed"] = 0  # the process failed even though its report looks clean
    return report


def run_web():
    code, log, _ = sh(["node", "build.mjs"], cwd=ROOT / "apps/web")
    if code != 0:
        return {"suite": "web-qa", "passed": 0, "total": 1, "checks": [{"name": "build", "ok": False, "detail": log[-400:]}]}
    return fresh_report(OUT / "web-qa.json", ["node", "qa.mjs", str(OUT / "web-qa.json")], cwd=ROOT / "apps/web", suite="web-qa")


def run_eval():
    binary = OUT / "eval-holdout"
    code, log, _ = build_core()
    if code == 0:
        code, log, _ = sh(["swiftc", *CORE_FLAGS, "qa/eval-holdout.swift", "-o", str(binary)])
    if code != 0:
        return {"suite": "eval-holdout", "passed": 0, "total": 1, "weeks": [], "error": log[-400:]}
    return fresh_report(OUT / "eval-holdout.json", [str(binary), str(OUT / "eval-holdout.json")], suite="eval-holdout")


# The sources each agent-run suite tests. A saved result counts only while these are unchanged.
AGENT_SOURCES = {"browser": ["apps/web/src", "apps/web/build.mjs", "apps/web/vercel.json", "qa/browser-sessions.js"],
                 "db": ["supabase/migrations", "qa/db-waitlist.sql"]}


def fingerprint(name):
    digest = hashlib.sha256()
    for root in AGENT_SOURCES[name]:
        path = ROOT / root
        for f in sorted(path.rglob("*") if path.is_dir() else [path]):
            if f.is_file():
                digest.update(str(f.relative_to(ROOT)).encode() + b"\0" + f.read_bytes())
    return digest.hexdigest()[:16]


def agent_suite(name):
    """Browser and database suites are run by an agent (see AGENTS.md) and saved into qa/out/
    with the fingerprint printed by `qa/run.py --fingerprint NAME`. A result saved against
    different sources is stale: it fails the gate until the suite is run again."""
    path = OUT / f"{name}.json"
    if not path.exists():
        return None
    result = json.loads(path.read_text())
    if result.get("fingerprint") != fingerprint(name):
        return {"suite": name, "passed": 0, "total": 1, "stale": True, "passedNodes": [], "failedNodes": [],
                "error": "stale: its sources changed since it ran; run it again"}
    return result


def coverage(flows, suites, partial=False):
    visited = {}
    for run in suites["self-test"]["runs"]:
        for node, count in run["nodes"].items():
            visited[node] = visited.get(node, 0) + count
    failing_rules = {f["rule"] for run in suites["self-test"]["runs"] for f in run["failures"]}
    page_of = lambda name: name[: name.index(".html") + 5] if ".html" in name else None  # "index.html.oneH1" → "index.html"
    web_bad = {page_of(c["name"]) for c in suites["web-qa"]["checks"] if not c["ok"]}
    web_ok = {page_of(c["name"]) for c in suites["web-qa"]["checks"] if c["ok"]} - web_bad
    status = {}
    for surface in flows["surfaces"]:
        for node in surface["nodes"]:
            nid, suite = node["id"], node["suite"]
            key = {"eval": "eval-holdout"}.get(suite, suite)
            if suites.get(key) and suites[key].get("skipped"):
                s = "skipped"
            elif suite == "manual":
                s = "manual"
            elif suite == "self-test":
                prefix = nid.split(".")[0]
                s = "fail" if any(r.startswith(prefix) for r in failing_rules) else ("pass" if visited.get(nid) else "missed")
            elif suite == "web-qa":
                page = nid.removeprefix("web.page.") + ".html"
                s = "fail" if page in web_bad else ("pass" if page in web_ok else "missed")
            elif suite == "checks":
                s = "pass" if suites["checks"]["passed"] == suites["checks"]["total"] else "fail"
            elif suite == "eval":
                e = suites["eval-holdout"]
                s = "pass" if e["total"] and e["passed"] == e["total"] else "fail"
            else:  # browser, db: run by an agent. Absent is a gap in a full run, a skip in a partial one.
                agent = suites.get(suite)
                s = ("skipped" if partial else "missed") if not agent else ("pass" if nid in agent.get("passedNodes", []) else "fail" if nid in agent.get("failedNodes", []) else "missed")
            status[nid] = s
    edges_taken = {}
    for run in suites["self-test"]["runs"]:
        for edge, count in run["edges"].items():
            edges_taken[edge] = edges_taken.get(edge, 0) + count
    return status, edges_taken


# ---------- report ----------

COLORS = {"pass": "#1f9d55", "fail": "#d64545", "missed": "#9aa1ae", "manual": "#d69e2e", "skipped": "#4b5563"}


def svg_flow_graph(flows, status, edges_taken):
    col_w, row_h, node_w, node_h = 300, 44, 250, 30
    pos, parts = {}, []
    height = max(len(s["nodes"]) for s in flows["surfaces"]) * row_h + 60
    for ci, surface in enumerate(flows["surfaces"]):
        x = 20 + ci * col_w
        parts.append(f'<text x="{x}" y="22" class="col">{html.escape(surface["label"])}</text>')
        for ri, node in enumerate(surface["nodes"]):
            y = 40 + ri * row_h
            pos[node["id"]] = (x, y)
    for surface in flows["surfaces"]:
        for e in surface["edges"]:
            if e["from"] in pos and e["to"] in pos:
                (x1, y1), (x2, y2) = pos[e["from"]], pos[e["to"]]
                taken = edges_taken.get(e["action"], 0) > 0 or surface["id"] != "mac"
                bend = 40 + (abs(y2 - y1) // 6)
                parts.append(f'<path d="M{x1 + node_w} {y1 + node_h/2} C{x1 + node_w + bend} {y1 + node_h/2} {x2 + node_w + bend} {y2 + node_h/2} {x2 + node_w} {y2 + node_h/2}" '
                             f'class="edge{"" if taken else " untaken"}"><title>{html.escape(e["action"])}</title></path>')
    for surface in flows["surfaces"]:
        for node in surface["nodes"]:
            x, y = pos[node["id"]]
            s = status.get(node["id"], "missed")
            parts.append(f'<g><rect x="{x}" y="{y}" width="{node_w}" height="{node_h}" rx="7" fill="{COLORS[s]}"/>'
                         f'<text x="{x + 10}" y="{y + 20}" class="node">{html.escape(node["label"])}</text>'
                         f'<title>{html.escape(node["id"])} · {s} · proven by {node["suite"]}</title></g>')
    width = 20 + len(flows["surfaces"]) * col_w + 60
    return f'<svg viewBox="0 0 {width} {height}" role="img" aria-label="Flow coverage graph">{"".join(parts)}</svg>'


def svg_trend(history):
    if not history:
        return "<p>No history yet.</p>"
    w, h, pad = 720, 220, 36
    n = len(history)
    xs = [pad + (w - 2 * pad) * (i / max(n - 1, 1)) for i in range(n)]
    def line(values, cls, top):
        pts = " ".join(f"{x:.1f},{h - pad - (h - 2 * pad) * (v / top if top else 0):.1f}" for x, v in zip(xs, values))
        return f'<polyline points="{pts}" class="{cls}"/>' + "".join(
            f'<circle cx="{x:.1f}" cy="{h - pad - (h - 2 * pad) * (v / top if top else 0):.1f}" r="3.5" class="{cls}"/>' for x, v in zip(xs, values))
    cov = [r["coverage"] for r in history]
    fails = [r["failures"] for r in history]
    top = max(max(fails), 1)
    labels = "".join(f'<text x="{x:.1f}" y="{h - 10}" class="tick">{i + 1}</text>' for i, x in enumerate(xs))
    return (f'<svg viewBox="0 0 {w} {h}" role="img" aria-label="Coverage and failures per run">'
            f'<line x1="{pad}" y1="{h - pad}" x2="{w - pad}" y2="{h - pad}" class="axis"/>'
            f'{line(cov, "cov", 100)}{line(fails, "fail", top)}{labels}'
            f'<text x="{pad}" y="16" class="legend cov-t">coverage % (0–100)</text>'
            f'<text x="{pad + 200}" y="16" class="legend fail-t">confirmed failures (0–{top})</text></svg>')


def svg_bars(items, label):
    if not items:
        return "<p>No data.</p>"
    w, bar_h = 720, 20
    top = max(v for _, v in items) or 1
    rows = "".join(
        f'<text x="0" y="{i * (bar_h + 6) + 15}" class="tick">{html.escape(str(k))}</text>'
        f'<rect x="150" y="{i * (bar_h + 6)}" width="{max(2, (w - 220) * v / top):.1f}" height="{bar_h}" rx="4" class="bar"/>'
        f'<text x="{156 + (w - 220) * v / top:.1f}" y="{i * (bar_h + 6) + 15}" class="tick">{v}</text>'
        for i, (k, v) in enumerate(items))
    return f'<svg viewBox="0 0 {w} {len(items) * (bar_h + 6)}" role="img" aria-label="{html.escape(label)}">{rows}</svg>'


def write_report(summary, suites, flows, status, edges_taken, history):
    counts = {k: sum(1 for v in status.values() if v == k) for k in COLORS}
    def card(name, s):
        if not s:
            return f'<div class="card none"><b>{name}</b><span>not run</span></div>'
        return f'<div class="card {"ok" if s["passed"] == s["total"] else "bad"}"><b>{name}</b><span>{s["passed"]}/{s["total"]}</span></div>'
    cards = "".join(card(name, s) for name, s in suites.items())
    failures = [f for run in suites["self-test"]["runs"] for f in run["failures"]]
    fail_rows = "".join(f'<li><b>{html.escape(f["rule"])}</b>: {html.escape(f["detail"])} '
                        f'<code>seed {f.get("seed")} · session {f.get("session")} · {" → ".join(f.get("trail", [])[-8:])}</code></li>'
                        for f in failures) or "<li>None.</li>"
    evals = [(f'week {w["week"]}', w.get("tableMatches", 0)) for w in suites["eval-holdout"].get("weeks", [])]
    page = f"""<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Understudy QA</title><style>
:root{{color-scheme:light dark;--bg:#101217;--fg:#eceef2;--muted:#9aa1ae;--card:#191c23}}
body{{margin:0;background:var(--bg);color:var(--fg);font:15px -apple-system,system-ui,sans-serif;padding:24px;max-width:1100px}}
h1{{margin:0 0 4px}} h2{{margin:32px 0 10px;font-size:18px}} p.sub{{color:var(--muted);margin:0 0 16px}}
.cards{{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px}}
.card{{background:var(--card);border-radius:10px;padding:12px;display:flex;justify-content:space-between;border-left:4px solid var(--muted)}}
.card.ok{{border-color:#1f9d55}} .card.bad{{border-color:#d64545}}
svg{{width:100%;height:auto;background:var(--card);border-radius:10px;padding:10px;box-sizing:border-box}}
.node{{fill:#fff;font-size:13px}} .col{{fill:var(--fg);font-weight:600;font-size:14px}}
.edge{{fill:none;stroke:#6b7280;stroke-width:1.2;opacity:.6}} .edge.untaken{{stroke:#d64545;stroke-dasharray:4 3;opacity:.9}}
.tick{{fill:var(--muted);font-size:12px}} .axis{{stroke:#4b5563}} .bar{{fill:#e0b22a}}
polyline{{fill:none;stroke-width:2}} .cov{{stroke:#1f9d55;fill:#1f9d55}} polyline.cov{{fill:none}} .fail{{stroke:#d64545;fill:#d64545}} polyline.fail{{fill:none}}
.legend{{font-size:12px}} .cov-t{{fill:#1f9d55}} .fail-t{{fill:#d64545}}
.key span{{display:inline-block;padding:2px 8px;border-radius:6px;margin-right:6px;color:#fff;font-size:13px}}
code{{color:var(--muted);font-size:12px}} li{{margin:6px 0}}
</style>
<h1>Understudy QA</h1><p class="sub">{html.escape(summary["date"])} · commit {summary["commit"]} · {summary["sessions"]} sessions × {len(summary["seeds"])} seeds · {summary["steps"]} simulated steps · coverage {summary["coverage"]}%</p>
<div class="cards">{cards}</div>
<h2>Flow graph</h2>
<p class="key"><span style="background:{COLORS["pass"]}">proven {counts["pass"]}</span><span style="background:{COLORS["fail"]}">failing {counts["fail"]}</span><span style="background:{COLORS["missed"]}">not reached {counts["missed"]}</span><span style="background:{COLORS["manual"]}">needs a server or a person {counts["manual"]}</span> Dashed red edges were never taken.</p>
{svg_flow_graph(flows, status, edges_taken)}
<h2>Confirmed failures</h2><ul>{fail_rows}</ul>
<h2>Trend across runs</h2>{svg_trend(history)}
<h2>Simulated actions taken</h2>{svg_bars(sorted(edges_taken.items(), key=lambda kv: -kv[1]), "Actions taken")}
<h2>Held-out evaluation · table lines matched</h2>{svg_bars(evals, "Held-out weeks")}
</html>"""
    (OUT / "report.html").write_text(page)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sessions", type=int, default=300)
    parser.add_argument("--seeds", default="1,2,3")
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--only", default="", help="comma list: checks,self-test,web-qa,eval-holdout")
    parser.add_argument("--fingerprint", choices=sorted(AGENT_SOURCES), help="print the fingerprint to save with an agent-run suite")
    args = parser.parse_args()
    if args.fingerprint:
        print(fingerprint(args.fingerprint)); return
    sessions, seeds = (40, [1]) if args.quick else (args.sessions, [int(s) for s in args.seeds.split(",")])
    OUT.mkdir(parents=True, exist_ok=True)

    if not args.skip_build:
        code, log, _ = sh(["apps/mac/scripts/bundle.sh"])
        if code != 0:
            print(log[-2000:]); sys.exit(1)
    only = set(filter(None, args.only.split(",")))
    runners = {"checks": run_checks, "self-test": lambda: run_self_test(sessions, seeds),
               "web-qa": run_web, "eval-holdout": run_eval}
    skipped = lambda name: {"suite": name, "passed": 0, "total": 0, "skipped": True, "checks": [], "runs": [], "weeks": []}
    suites = {name: (run() if not only or name in only else skipped(name)) for name, run in runners.items()}
    suites.update({"browser": agent_suite("browser"), "db": agent_suite("db")})
    flows = json.loads((ROOT / "qa/flows.json").read_text())
    status, edges_taken = coverage(flows, suites, partial=bool(only))
    automated = [v for v in status.values() if v not in ("manual", "skipped")]
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    summary = {
        "date": datetime.datetime.now().isoformat(timespec="seconds"), "commit": commit, "sessions": sessions, "seeds": seeds,
        "steps": sum(r["steps"] for r in suites["self-test"]["runs"]),
        "failures": sum(len(r["failures"]) for r in suites["self-test"]["runs"]),
        "coverage": round(100 * sum(v == "pass" for v in automated) / max(len(automated), 1), 1),
        "suites": {k: (f'{v["passed"]}/{v["total"]}' if v else "not run") for k, v in suites.items()},
    }
    (OUT / "run.json").write_text(json.dumps({"summary": summary, "suites": suites, "coverage": status}, indent=2))
    history_path = ROOT / "qa/history.jsonl"
    with history_path.open("a") as f:
        f.write(json.dumps(summary) + "\n")
    history = [json.loads(l) for l in history_path.read_text().splitlines() if l.strip()]
    write_report(summary, suites, flows, status, edges_taken, history)

    print(json.dumps(summary, indent=2))
    # The gate: every suite that ran (including loaded agent suites) passed, and no automated node
    # of a suite that ran is failing or unreached.
    failed = [k for k, v in suites.items() if v and not v.get("skipped") and v["passed"] != v["total"]]
    if not only:
        failed += [f"{k} (not run)" for k in AGENT_SOURCES if suites.get(k) is None]
    uncovered = [n for n, v in status.items() if v in ("fail", "missed")]
    if uncovered:
        failed.append(f"coverage ({len(uncovered)} nodes: {', '.join(uncovered[:8])})")
    print("gate:", "PASS" if not failed else f"FAIL {failed}")
    print(f"report: {OUT / 'report.html'}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
