// Simulated visitors for the website. Paste into the console of a page served from apps/web/dist
// (for example `npx serve apps/web/dist`), then save the returned JSON as qa/out/browser.json.
// Network calls to Supabase are answered by a fake server, so nothing reaches the real waitlist.
// Each visitor runs in an iframe at a phone, tablet, or desktop width.
async function understudyBrowserSessions(visitors = 200, seed = 1) {
  let state = seed >>> 0;
  const rand = () => ((state = (state * 1664525 + 1013904223) >>> 0) / 2 ** 32);
  const pick = (a) => a[Math.floor(rand() * a.length)];
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const passed = new Set(), failures = [];
  const fail = (visitor, rule, detail) => failures.length < 50 && failures.push({ visitor, rule, detail });
  const emails = ["maria@agency.pe", "  Leo.Park@Norte.studio ", "ana+test@consult.co", "x@y.io", "nope", "a@b", "", "space @x.com"];
  const valid = (e) => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e.trim());

  async function open(path, width) {
    const frame = document.createElement("iframe");
    frame.style.cssText = `position:absolute;left:-5000px;top:0;width:${width}px;height:900px;border:0`;
    frame.src = path;
    document.body.appendChild(frame);
    await new Promise((r) => (frame.onload = r));
    await wait(60);
    const win = frame.contentWindow;
    const calls = [];
    const errors = [];
    win.addEventListener("error", (e) => errors.push(String(e.message)));
    // Fake Supabase: join returns a token; details returns nothing. Some visitors get failures.
    win.__mode = "ok";
    win.fetch = async (url, opts) => {
      calls.push({ url: String(url), body: JSON.parse(opts.body) });
      if (!String(url).startsWith("https://idwgaqnpheittqtllhzl.supabase.co/rest/v1/rpc/")) throw new Error("unexpected host");
      if (win.__mode === "offline") throw new TypeError("Failed to fetch");
      if (win.__mode === "bad") return new Response(JSON.stringify({ message: "invalid email" }), { status: 400 });
      if (String(url).endsWith("join_waitlist")) return new Response(JSON.stringify("11111111-2222-3333-4444-555555555555"), { status: 200 });
      return new Response(null, { status: 204 });  // what Supabase returns for a void function
    };
    return { frame, win, doc: frame.contentDocument, calls, errors, close: () => frame.remove() };
  }
  const shown = (el) => el && !el.hidden && el.ownerDocument.defaultView.getComputedStyle(el).display !== "none";

  for (let v = 0; v < visitors; v++) {
    const width = pick([375, 390, 768, 1024, 1440]);
    const flow = pick(["hero", "hero", "early", "early", "demo", "menu"]);
    try {
      if (flow === "hero" || flow === "early") {
        const path = flow === "hero" ? "/" : "/early-access";
        let p = await open(path, width);
        p.win.sessionStorage.clear();
        p.close(); p = await open(path, width);
        if (rand() < 0.2) p.win.Storage.prototype.setItem = () => { throw new Error("blocked"); };  // storage blocked
        const form = p.doc.querySelector(flow === "hero" ? "#hero-form" : "#wl-form");
        const input = form.querySelector("input[type=email]");
        const email = pick(emails);
        p.win.__mode = rand() < 0.1 ? "offline" : rand() < 0.1 ? "bad" : "ok";
        input.value = email;
        const button = form.querySelector("button[type=submit]");
        button.click();
        if (rand() < 0.3) button.click();  // impatient double click
        await wait(120);
        const status = form.parentElement.querySelector(".inline-status, .status");
        if (!valid(email)) {
          if (p.calls.length) fail(v, "form.invalidNotSent", `sent ${JSON.stringify(email)}`);
          if (!/Enter an email/.test(status.textContent)) fail(v, "form.invalidMessage", status.textContent);
        } else if (p.win.__mode !== "ok") {
          if (!shown(form)) fail(v, "form.errorKeepsForm", "form hidden after a failed request");
          if (!status.textContent || button.disabled) fail(v, "form.errorRecoverable", `status "${status.textContent}", disabled ${button.disabled}`);
        } else {
          if (p.calls.filter((c) => c.url.endsWith("join_waitlist")).length !== 1) fail(v, "form.oneRequest", `${p.calls.length} requests`);
          if (p.calls[0] && p.calls[0].body.p_email !== email.trim()) fail(v, "form.trimsEmail", p.calls[0].body.p_email);
          if (flow === "hero") {
            if (!shown(p.doc.querySelector("#hero-joined")) || shown(form)) fail(v, "hero.joinedState", "joined state not shown");
            else passed.add("web.hero.joined");
          } else {
            if (!shown(p.doc.querySelector("#details-panel")) || shown(p.doc.querySelector("#join-panel"))) fail(v, "ea.detailsState", "details not shown");
            else passed.add("web.ea.details");
            // Optional details, saved once with the token from join.
            p.doc.querySelector("#d-task").value = pick(["", "Monday GA4 + Meta report for 8 clients", "x".repeat(1500)]);
            p.doc.querySelector("#d-work").value = pick(["agency", "consultancy", "freelancer", "inhouse", "other"]);
            p.doc.querySelector("#d-mac").value = pick(["notch", "no-notch", "not-mac"]);
            p.doc.querySelector("#d-save").click();
            await wait(120);
            const details = p.calls.filter((c) => c.url.endsWith("add_waitlist_details"));
            if (details.length !== 1 || details[0].body.p_token !== "11111111-2222-3333-4444-555555555555") fail(v, "ea.detailsToken", JSON.stringify(details));
            else if (details[0].body.p_task.length > 1200) fail(v, "ea.detailsCap", `task ${details[0].body.p_task.length} chars`);
            else if (!/Saved/.test(p.doc.querySelector("#d-status").textContent) || !p.doc.querySelector("#d-save").disabled) fail(v, "ea.savedState", p.doc.querySelector("#d-status").textContent);
            else passed.add("web.ea.done");
          }
          // Reload mid-flow: the signup is remembered in this tab (unless storage was blocked).
          const blocked = p.win.Storage.prototype.setItem.toString().includes("blocked");
          p.close();
          if (!blocked) {
            const again = await open(path, width);
            const kept = flow === "hero" ? shown(again.doc.querySelector("#hero-joined")) : shown(again.doc.querySelector("#details-panel"));
            if (!kept) fail(v, "form.reloadKeepsSignup", "signup forgotten after reload");
            again.close();
          }
          p = null;
        }
        if (p) { if (p.errors.length) fail(v, "page.noScriptErrors", p.errors.join("; ")); p.close(); }
      } else if (flow === "demo") {
        const p = await open("/", width);
        const chips = [...p.doc.querySelectorAll(".chip")];
        const chip = pick(chips);
        chip.click();
        await wait(30);
        if (chip.getAttribute("aria-pressed") !== "true") fail(v, "demo.chipPressed", chip.dataset.phase);
        const play = p.doc.querySelector("#play");
        if (play.textContent !== "Play") fail(v, "demo.chipPauses", play.textContent);
        play.click();
        if (play.textContent !== "Pause") fail(v, "demo.playResumes", play.textContent);
        else passed.add("web.demo.controls");
        if (p.errors.length) fail(v, "page.noScriptErrors", p.errors.join("; "));
        p.close();
      } else {
        const page = pick(["/", "/workflow", "/rehearsal", "/receipts", "/what-exists", "/pricing", "/early-access", "/privacy"]);
        const p = await open(page, width);
        const nav = p.doc.querySelector(".nav");
        const links = [...nav.querySelectorAll("a")].map((a) => a.getAttribute("href"));
        const overflow = p.doc.documentElement.scrollWidth > width + 1;
        if (p.win.getComputedStyle(nav).display === "none") fail(v, "menu.visible", `${page} at ${width}px`);
        else if (links.join() !== "/workflow,/rehearsal,/receipts,/what-exists,/pricing") fail(v, "menu.links", links.join());
        else if (overflow) fail(v, "page.noSideScroll", `${page} at ${width}px`);
        else if (width < 800) passed.add("web.menu.mobile");
        p.close();
      }
    } catch (e) {
      fail(v, "session.crashed", String(e));
    }
  }
  const nodes = ["web.hero.joined", "web.ea.details", "web.ea.done", "web.demo.controls", "web.menu.mobile"];
  const failedRules = new Set(failures.map((f) => f.rule));
  return {
    suite: "browser", visitors, seed, date: new Date().toISOString(),
    passed: failures.length ? 0 : 1, total: 1,
    passedNodes: nodes.filter((n) => passed.has(n) && !failedRules.size),
    failedNodes: failedRules.size ? nodes : [],
    failures,
  };
}
