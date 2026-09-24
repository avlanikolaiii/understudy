// Builds the static pre-launch site into dist/. No dependencies: `node build.mjs`.
// Each page in src/pages starts with a front-matter block:
//   <!-- title: ... | description: ... | nav: workflow | scripts: demo -->
import { cpSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";

const src = new URL("./src/", import.meta.url);
const dist = new URL("./dist/", import.meta.url);
rmSync(dist, { recursive: true, force: true });
mkdirSync(dist, { recursive: true });
cpSync(new URL("assets/", src), new URL("assets/", dist), { recursive: true });
cpSync(new URL("static/", src), dist, { recursive: true });

const layout = readFileSync(new URL("layout.html", src), "utf8");
const version = createHash("sha256")
  .update(readdirSync(new URL("assets/", src)).map((f) => readFileSync(new URL(`assets/${f}`, src))).join(""))
  .digest("hex").slice(0, 10);
const escape = (s) => s.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");

for (const file of readdirSync(new URL("pages/", src)).filter((f) => f.endsWith(".html"))) {
  const raw = readFileSync(new URL(`pages/${file}`, src), "utf8");
  const head = raw.match(/^<!--(.*?)-->\n/s);
  if (!head) throw new Error(`${file} is missing its front-matter comment`);
  const meta = Object.fromEntries(head[1].split("|").map((part) => {
    const at = part.indexOf(":");
    return [part.slice(0, at).trim(), part.slice(at + 1).trim()];
  }));
  if (!meta.title || !meta.description) throw new Error(`${file} needs a title and a description`);
  const scripts = (meta.scripts || "").split(",").map((s) => s.trim()).filter(Boolean)
    .map((s) => `<script src="/assets/${s}.js?v=${version}"></script>`).join("\n");
  const html = layout
    .replace(/\{\{current:([a-z-]+)\}\}/g, (_, key) => (key === meta.nav ? ' aria-current="page"' : ""))
    .replaceAll("{{title}}", escape(meta.title))
    .replaceAll("{{description}}", escape(meta.description))
    .replaceAll("{{version}}", version)
    .replace("{{scripts}}", scripts)
    .replace("{{content}}", raw.slice(head[0].length));
  if (/\{\{/.test(html)) throw new Error(`${file} left an unfilled placeholder`);
  writeFileSync(new URL(file, dist), html);
}
console.log(`Built ${readdirSync(dist).filter((f) => f.endsWith(".html")).length} pages into apps/web/dist (assets v${version}).`);
