/* Early-access forms. Signups go to Supabase through two narrow functions. */
(function () {
  const cfg = window.UNDERSTUDY || {};
  const $ = (s) => document.querySelector(s);
  const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
  const KEY = "understudy-waitlist";

  // Session storage remembers this tab's signup so the details step can follow it.
  // If the browser blocks storage, the signup is still kept in memory for this page.
  let memory = null;
  const store = {
    get() { try { return JSON.parse(sessionStorage.getItem(KEY)) || memory; } catch (e) { return memory; } },
    set(v) { memory = v; try { sessionStorage.setItem(KEY, JSON.stringify(v)); } catch (e) {} }
  };

  async function rpc(name, body) {
    const res = await fetch(`${cfg.supabaseURL}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: { "apikey": cfg.supabaseKey, "Content-Type": "application/json" },
      body: JSON.stringify(body)
    });
    const data = await res.json().catch(() => null);
    if (!res.ok) { const err = new Error((data && data.message) || res.statusText); err.status = res.status; throw err; }
    return data;
  }

  function setStatus(node, msg, kind) {
    if (!node) return;
    node.textContent = msg;
    node.className = node.className.split(" ")[0] + (kind ? " " + kind : "");
  }
  const errText = (err) => (err && err.status === 400)
    ? "That email doesn't look right. Try again."
    : "That didn't save. Check your connection and try again.";

  async function join(form, source, done) {
    const input = form.querySelector("input[type=email]");
    const status = form.parentElement.querySelector(".inline-status, .status");
    const btn = form.querySelector("button[type=submit]");
    const email = input.value.trim();
    if (!EMAIL.test(email)) { setStatus(status, "Enter an email address like you@agency.com.", "err"); input.focus(); return; }
    const trap = form.querySelector(".hp input");
    if (trap && trap.value) { done({ email, token: null, details: true }); return; }   // bots fill hidden fields
    btn.disabled = true; setStatus(status, "Saving…");
    try {
      const token = await rpc("join_waitlist", { p_email: email, p_source: source });
      const state = { email, token, details: false };
      store.set(state); setStatus(status, ""); done(state);
    } catch (err) { setStatus(status, errText(err), "err"); }
    finally { btn.disabled = false; }
  }

  // Home: the hero form.
  const hero = $("#hero-form");
  if (hero) {
    const showJoined = (s) => {
      document.querySelectorAll(".j-email").forEach((n) => { n.textContent = s.email; });
      hero.hidden = true; $("#hero-joined").hidden = false;
    };
    const saved = store.get();
    if (saved) showJoined(saved);
    hero.addEventListener("submit", (e) => { e.preventDefault(); join(hero, "home", showJoined); });
  }

  // Early access: join, then three optional questions.
  const wl = $("#wl-form");
  if (wl) {
    const showDetails = (s) => {
      document.querySelectorAll(".j-email").forEach((n) => { n.textContent = s.email; });
      $("#join-panel").hidden = true; $("#details-panel").hidden = false;
      if (s.details) { $("#details-form").hidden = true; $("#details-done").hidden = false; }
    };
    const saved = store.get();
    if (saved) showDetails(saved);
    wl.addEventListener("submit", (e) => { e.preventDefault(); join(wl, "early-access", showDetails); });

    $("#details-form").addEventListener("submit", async (e) => {
      e.preventDefault();
      const s = store.get(); const btn = $("#d-save"); const st = $("#d-status");
      if (!s || !s.token) { setStatus(st, "Join the list first, then add your answers.", "err"); return; }
      btn.disabled = true; setStatus(st, "Saving…");
      try {
        await rpc("add_waitlist_details", {
          p_email: s.email, p_token: s.token,
          p_work: $("#d-work").value, p_mac: $("#d-mac").value, p_task: $("#d-task").value.trim().slice(0, 1200)
        });
        store.set(Object.assign({}, s, { details: true, token: null }));
        setStatus(st, "Saved. Thank you, this shapes what we build first.", "ok");
        $("#details-form").querySelectorAll("textarea,select,button").forEach((n) => { n.disabled = true; });
      } catch (err) { setStatus(st, errText(err), "err"); btn.disabled = false; }
    });
  }
})();
