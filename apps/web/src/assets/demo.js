// The hero's notch demonstration, unchanged from the landing page. A concept demonstration, not the app.
/* ================= notch demo ================= */
(function(){
  const $ = (s) => document.querySelector(s);
  const notch = $("#notch"), label = $("#n-label"), meta = $("#n-meta"), body = $("#n-body");
  const voice = $("#voice"), voiceText = $("#voice-text"), voiceLbl = $("#voice-lbl"), cap = $("#demo-cap"), playBtn = $("#play");
  const winTitle = $("#win-title"), winRo = $("#win-ro"), docTitle = $("#doc-title");
  const F = ["sessions","leads","spend","high"];
  const blank = () => ({phase:"show", open:false, mode:"", label:"", meta:"", rows:[], fields:{}, voice:"", vl:"YOU", win:"Norte Studio · weekly update", doc:"Norte Studio · Week 38", ro:false, cap:""});

  const frames = [
    {d:2000, f:s=>{Object.assign(s, blank()); s.cap="Monday, 9:02. Understudy waits in the notch while you start Norte Studio's weekly update.";}},
    {d:1300, f:s=>{s.vl="YOU PRESS"; s.voice="⌥ Space"; s.cap="You start it with the shortcut or a click on the notch.";}},
    {d:1000, f:s=>{s.open=true; s.mode="watch"; s.label="Watching"; s.meta="0:02"; s.voice=""; s.cap="The dot pulses while it watches. It notes each app, field, and value, not video of your screen.";}},
    {d:1300, f:s=>{s.meta="0:09"; s.rows.push({app:"Sheets", t:"opened “Norte – campaign data”"});}},
    {d:1300, f:s=>{s.meta="0:21"; s.rows.push({app:"Sheets", t:"copied week 38 totals"}); Object.assign(s.fields,{sessions:"18,420", leads:"312", spend:"$4,850"});}},
    {d:1300, f:s=>{s.meta="0:40"; s.rows.push({app:"Drive", t:"read this week's notes"}); s.fields.high="Launch video: 41% of new leads";}},
    {d:1300, f:s=>{s.meta="1:12"; s.rows.push({app:"Sheets", t:"tracker row 14 → Ready", cls:"ok"});}},
    {d:1300, f:s=>{s.meta="1:30"; s.rows.push({app:"Gmail", t:"drafted email to Leo"});}},
    {d:2300, f:s=>{s.meta="1:34"; s.vl="YOU TYPE IN THE NOTCH"; s.voice="If a number's missing, ask me first."; s.rows.push({app:"Your rule", t:"missing number → ask me", cls:"said"}); s.cap="Type a rule into the notch as you go, and it's saved with the skill.";}},
    {d:3400, f:s=>{s.phase="learn"; s.mode="learned"; s.vl="YOU PRESS"; s.voice="⌥ Space to stop"; s.label="New skill: Weekly client update"; s.meta="6 steps";
      s.rows=[{app:"Sheets", t:"→ connector", end:"✓", endcls:"ok"},{app:"Docs", t:"→ connector", end:"✓", endcls:"ok"},{app:"Gmail", t:"→ connector, draft only", end:"✓", endcls:"ok"},{app:"Summary", t:"→ AI step + memory", cls:"said"}];
      s.cap="It writes the skill and links each step to a connector. Only the summary needs an AI model.";}},
    {d:1300, f:s=>{s.phase="rehearse"; s.mode="rehearse"; s.voice=""; s.label="Rehearsing · read-only"; s.meta="3 past weeks"; s.rows=[]; s.fields={}; s.ro=true; s.win="Rehearsal · its version"; s.doc="Norte Studio · Week 36";
      s.cap="Before you hand it off, it redoes three past weeks from the raw inputs only. It never sees the reports you sent, and nothing live changes.";}},
    {d:1400, f:s=>{s.rows.push({app:"Week 36", t:"vs. what you sent", end:"match", endcls:"ok"}); s.fields={sessions:"17,905", leads:"298", spend:"$4,610", high:"Webinar replay: 22% of leads"};}},
    {d:1400, f:s=>{s.rows.push({app:"Week 37", t:"vs. what you sent", end:"match", endcls:"ok"}); s.doc="Norte Studio · Week 37"; s.fields={sessions:"18,102", leads:"305", spend:"$4,720", high:"New landing page live"};}},
    {d:3200, f:s=>{s.rows.push({app:"Week 38", t:"“click rate” vs “CTR”", end:"1 diff", endcls:"hold"}); s.doc="Norte Studio · Week 38"; s.fields={sessions:"18,420", leads:"312", spend:"$4,850", high:"Launch video: 41% of new leads"};
      s.cap="Two exact matches and one wording difference. You fix it for Norte Studio only, then hand it off.";}},
    {d:1300, f:s=>{s.phase="handoff"; s.mode="run"; s.label="Running · Week 39"; s.meta="Mon 9:12"; s.rows=[]; s.ro=false; s.win="Norte Studio · weekly update"; s.doc="Norte Studio · Week 39"; s.fields={};
      s.cap="Next Monday it runs on its own. This week, one number is missing from the source sheet.";}},
    {d:1500, f:s=>{s.rows.push({app:"Sheets", t:"ad spend · C12 empty", end:"blocked", endcls:"hold"}); s.fields={sessions:"19,730", leads:"344", spend:"MISSING", high:"Case study page: top new page"};}},
    {d:1400, f:s=>{s.rows.push({app:"Report", t:"saved as incomplete draft", end:"partly", endcls:"hold"}); s.doc="Norte Studio · Week 39 (DRAFT, incomplete)";}},
    {d:1300, f:s=>{s.rows.push({app:"Tracker", t:"row 14 → Needs input", end:"done", endcls:"ok"});}},
    {d:1300, f:s=>{s.rows.push({app:"Email", t:"not drafted: report incomplete", end:"held", endcls:"hold"});}},
    {d:4600, f:s=>{s.label="Receipt · not ready to send"; s.meta="1m 40s"; s.rows=[{app:"Spend", t:"blocked · not verifiable", end:"needs you", endcls:"hold"},{app:"Report", t:"partly done", end:"verified", endcls:"ok"},{app:"Tracker", t:"needs input", end:"verified", endcls:"ok"},{app:"Email", t:"held back", end:"verified", endcls:"ok"}];
      s.cap="Missing spend changes every later step: the report stays an incomplete draft, the tracker says it needs input, and no client email is drafted. The receipt shows what it read back to confirm each one.";}}
  ];
  const phaseStart = {show:0, learn:9, rehearse:10, handoff:14};
  const lastFrame = frames.length - 1;
  let s = blank(), i = 0, timer = null, playing = true, prev = {};
  const reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };

  function render(){
    notch.classList.toggle("open", s.open);
    notch.classList.toggle("watch", s.mode === "watch");
    notch.classList.toggle("rehearse", s.mode === "rehearse");
    label.textContent = s.label; meta.textContent = s.meta;
    winTitle.textContent = s.win; winRo.hidden = !s.ro; docTitle.textContent = s.doc;
    body.textContent = "";
    if (s.mode){
      const ul = el("ul","nlist");
      s.rows.slice(-4).forEach(r => {
        const li = el("li"); li.appendChild(el("span","app",r.app)); li.appendChild(el("span", r.cls || "", r.t));
        if (r.end) li.appendChild(el("span","end " + (r.endcls || ""), r.end));
        ul.appendChild(li);
      });
      body.appendChild(ul);
    }
    F.forEach(k => {
      const n = document.getElementById("f-" + k), v = s.fields[k];
      const missing = v === "MISSING";
      n.textContent = missing ? "Missing: flagged" : (v || "—");
      n.classList.toggle("empty", !v); n.classList.toggle("missing", missing);
      if (v && v !== prev[k] && !reduce){ n.classList.remove("flash"); void n.offsetWidth; n.classList.add("flash"); }
    });
    prev = Object.assign({}, s.fields);
    if (s.voice){ voiceLbl.textContent = s.vl; voiceText.textContent = s.voice; voice.classList.add("show"); } else voice.classList.remove("show");
    if (s.cap) cap.textContent = s.cap;
    document.querySelectorAll(".chip").forEach(c => c.setAttribute("aria-pressed", String(c.dataset.phase === s.phase)));
  }
  function jumpTo(idx){ s = blank(); for (let k = 0; k <= idx; k++) frames[k].f(s); i = idx; render(); }
  function schedule(){
    clearTimeout(timer);
    if (!playing) return;
    timer = setTimeout(() => { i = (i + 1) % frames.length; if (i === 0) s = blank(); frames[i].f(s); render(); schedule(); }, frames[i].d);
  }
  function setPlaying(p){ playing = p; playBtn.textContent = p ? "Pause" : "Play"; cap.setAttribute("aria-live", p ? "off" : "polite"); schedule(); }
  document.querySelectorAll(".chip").forEach(c => c.addEventListener("click", () => { setPlaying(false); jumpTo(c.dataset.phase === "handoff" ? lastFrame : phaseStart[c.dataset.phase]); }));
  playBtn.addEventListener("click", () => setPlaying(!playing));
  if (reduce){ jumpTo(lastFrame); setPlaying(false); } else { jumpTo(5); setPlaying(true); }
})();

