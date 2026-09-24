// Static QA for the built site. Run after `node build.mjs`: `node qa.mjs [out.json]`.
// Checks every page in dist/ without a browser, dependency-free. Exits 1 on any failure.
import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";

const dist = new URL("./dist/", import.meta.url);
const read = (path) => readFileSync(new URL(path, dist), "utf8");
const pages = readdirSync(dist).filter((f) => f.endsWith(".html"));
const checks = [];
const check = (name, ok, detail = "") => checks.push({ name, ok: Boolean(ok), detail });

// Which menu item each page should mark as current.
const expectedCurrent = {
  "index.html": null, "workflow.html": "/workflow", "rehearsal.html": "/rehearsal", "receipts.html": "/receipts",
  "what-exists.html": "/what-exists", "pricing.html": "/pricing", "early-access.html": "/early-access",
  "privacy.html": null, "404.html": null,
};
const resolve = (href) => {
  const path = href.split(/[?#]/)[0];
  if (path === "/") return "index.html";
  if (path.startsWith("/assets/") || /\.[a-z]+$/.test(path)) return path.slice(1);
  return `${path.slice(1)}.html`;
};

check("site.allPagesBuilt", Object.keys(expectedCurrent).every((p) => pages.includes(p)),
  `missing: ${Object.keys(expectedCurrent).filter((p) => !pages.includes(p)).join(", ")}`);

for (const page of pages) {
  const html = read(page);
  const h1s = (html.match(/<h1[\s>]/g) || []).length;
  check(`${page}.oneH1`, h1s === 1, `${h1s} h1 elements`);
  check(`${page}.noPlaceholders`, !/\{\{/.test(html));
  check(`${page}.noDownload`, !/download/i.test(html.replace(/<svg[\s\S]*?<\/svg>/g, "")));
  check(`${page}.titleAndDescription`, /<title>[^<]+<\/title>/.test(html) && /<meta name="description" content="[^"]+"/.test(html));
  const internal = [...html.matchAll(/(?:href|src)="(\/[^"]*)"/g)].map((m) => m[1]);
  const broken = internal.filter((href) => !existsSync(new URL(resolve(href), dist)));
  check(`${page}.internalLinks`, broken.length === 0, broken.join(", "));
  // Attributes can come in any order (the header's call to action has class before href).
  const current = [...html.matchAll(/<a\b[^>]*aria-current="page"[^>]*>/g)].map((m) => m[0].match(/href="([^"]+)"/)?.[1]);
  const want = expectedCurrent[page];
  check(`${page}.menuCurrent`, want ? current.length === 1 && current[0] === want : current.length === 0,
    `current: ${current.join(", ") || "none"}`);
}

// Every element id the scripts look up must exist on the pages that load them.
const ids = (html) => new Set([...html.matchAll(/\bid="([^"]+)"/g)].map((m) => m[1]));
const scriptIds = (file) => [...new Set([...readFileSync(new URL(`src/assets/${file}`, import.meta.url), "utf8")
  .matchAll(/\$\("#([a-zA-Z0-9-]+)"\)/g)].map((m) => m[1]))];
const home = ids(read("index.html"));
const early = ids(read("early-access.html"));
const demoMissing = scriptIds("demo.js").filter((id) => !home.has(id));
check("home.demoElements", demoMissing.length === 0, demoMissing.join(", "));
const siteMissing = scriptIds("site.js").filter((id) => !home.has(id) && !early.has(id));
check("forms.scriptElements", siteMissing.length === 0, siteMissing.join(", "));
const heroMissing = ["hero-form", "hero-email", "hero-joined", "hero-status"].filter((id) => !home.has(id));
check("home.heroForm", heroMissing.length === 0, heroMissing.join(", "));
const eaMissing = ["wl-form", "wl-email", "wl-status", "join-panel", "details-panel", "details-form", "d-task", "d-work",
  "d-mac", "d-save", "d-status", "details-done"].filter((id) => !early.has(id));
check("earlyAccess.forms", eaMissing.length === 0, eaMissing.join(", "));
check("forms.honeypot", /class="hp"/.test(read("index.html")) && /class="hp"/.test(read("early-access.html")));

// The Content-Security-Policy must allow the Supabase project the forms call, and nothing else.
const vercel = JSON.parse(readFileSync(new URL("vercel.json", import.meta.url), "utf8"));
const csp = vercel.headers.flatMap((h) => h.headers).find((h) => h.key === "Content-Security-Policy")?.value || "";
const supabase = readFileSync(new URL("src/assets/config.js", import.meta.url), "utf8").match(/supabaseURL:\s*"([^"]+)"/)?.[1];
check("csp.allowsSupabase", supabase && csp.includes(`connect-src ${supabase}`), `connect-src vs ${supabase}`);
check("csp.scriptsSelfOnly", /script-src 'self'(;|$)/.test(csp));
check("config.publishableKeyOnly", !/sb_secret_|service_role/.test(readFileSync(new URL("src/assets/config.js", import.meta.url), "utf8")));

const failed = checks.filter((c) => !c.ok);
const out = process.argv[2];
if (out) writeFileSync(out, JSON.stringify({ suite: "web-qa", passed: checks.length - failed.length, total: checks.length, checks }, null, 2));
for (const c of failed) console.log(`FAIL ${c.name}: ${c.detail}`);
console.log(`web-qa: ${checks.length - failed.length}/${checks.length} checks passed`);
process.exit(failed.length ? 1 : 0);
