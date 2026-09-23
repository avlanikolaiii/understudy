# Understudy: product context recovered from Claude

Reviewed September 23, 2026. This is an internal synthesis of the product
conversation and its later corrections, not a new feature commitment or proof
that the concept works. Follow `AGENTS.md` for the current build order and gates.

## Sources

- [Service landing page and waitlist](https://claude.ai/code/session_01PKSsiu3jxQbv9p7b2dLafg)
- [Service landing page and waitlist (fork)](https://claude.ai/code/session_01XveEVAeGhN6C4Mt7fAC2RG)
- [Understudy landing page and waitlist](https://claude.ai/artifact/EXma3rHzVLq9LHXCUaiB3B)
- [Understudy Prototype Plan](https://claude.ai/artifact/9dWdJh1eT3FuscykLSwATb)

The conversations were reviewed through the signed-in Claude browser UI, along
with the rendered artifact contents. No messages or waitlist entries were
submitted. Earlier assistant proposals are not treated as user decisions simply
because they appeared on a landing page.

## What the user is building

Understudy is a persistent native Mac companion. A person starts Watch, does a
recurring task their usual way, and adds rules as needed. Understudy should turn
that demonstration into an inspectable skill, rehearse on different inputs, and
eventually run the work with verifiable results.

The notch is the signature companion. In the September 23 continuation, the user
explicitly required teaching from the main app too and a more Mac-native window.
The workspace, notch, menu bar, and keyboard are complementary entry points. Voice is a later feature.
The user rejected recording a video and uploading it as the core experience.
Watching is deliberate, with a visible indicator; it is not always-on capture.

The user explicitly rejected exporting skills to run inside Claude or ChatGPT.
Understudy owns execution, connections, memory, and the run state. Models are
called from inside Understudy for steps that need judgment. Stable steps use
connectors. Connector execution is intended to avoid taking over the user's
mouse and to reduce model usage; profitability has not been established.

Memory is central to personalization: the user's context, writing preferences,
people, approvals, and client-specific rules should make work precise. Memories
need sources and correction mechanisms. For the first prototype, corrections
apply only to the current workflow. Client-wide and global scope come later.

## The chosen first experience

- Initial customer hypothesis: Mac-based agencies and consultancies, with Peru
  as the first market discussed. This is not validated demand.
- Flagship story: source figures and notes → report in the user's template →
  tracker status → client email waiting for approval.
- Narrow technical prototype: one sheet input, one Markdown report, rehearsal,
  a missing-figure case, and a basic receipt. Real tracker/email writes come later.
- Rehearsal uses only the inputs available for that past example. Finished
  reports are withheld until comparison. No writes to any connected account.
- Status describes what happened. Evidence describes the independent read-back
  check. A successful API response alone must not become “Verified.”
- Missing spend must affect downstream readiness: incomplete report, tracker
  needing input, and no client email draft. Never estimate the absent value.
- The approved headline is “Show it once. Then hand it off.” The absolute
  “Never do it again” was superseded.

## Decisions to preserve

- One English landing page. The separate Peru page was explicitly removed.
- Provisional pricing: Free $0 with up to five skills; Pro $15/month;
  Team $30/person/month. Included usage remains unresolved.
- “Cover for me” is a future Team concept: transfer selected responsibilities
  and exceptions to a teammate using their own accounts, without transferring
  private credentials or unrelated memory.
- Distribution: signed/notarized DMG, zip for GitHub/Sparkle updates, no
  Homebrew, no Mac App Store. Open source is the stated direction; the page's
  Apache 2.0 label is not evidence of completed licensing work in this repo.
- Model choices recorded in the handoff are Claude Opus 5.5 and GPT-5.6 Sol.
  Do not reuse the older conversation's model-price table as verified pricing.
- The user explicitly chose Supabase and Google/Apple sign-in. Claude
  interpreted “give me a link” as also including email-link sign-in; that is in
  the existing implementation and handoff.

## Latest priority and actual state

The later user instruction paused capture experiments and customer validation,
preserved their files, and prioritized a clickable native app. The user then
explicitly required accounts and connections, rejecting a local-only product.
Sample mode remains useful for trying the interface without an account.

Build order: simulated Watch → simulated skill review saved to the account →
read-only rehearsal → run and receipt → Google Sheets read-only connector →
server-side AI proxy. The simulation is a temporary UI milestone, not evidence
that demonstration-based learning works.

The Watch slice was built in this session. See `watch-slice.md` for behavior and
verification limits. Existing standalone workspace code is a separate local
demo with fixed sample outputs. Its sample skills are not learned procedures,
and its notes are not enforced rules. Account-dependent flows still require
configuration and end-to-end verification.

## Gaps to resolve as the approved slices are built

1. **Keep one coherent teaching flow.** The workspace and notch now share one
   Watch session, and demo notes carry into the local sample-skill review.
   Account-backed skill definitions, editable steps, and AI learning are still
   future work. Keep the simulation label visible.
2. **Reconcile data location before making promises.** The landing page says
   skills, memory, and receipts stay on the Mac with optional cloud sync. The
   later prototype direction ties data to accounts and Supabase. Define what
   is stored where and when sync happens; do not silently claim both designs
   are already implemented.
3. **Use the current repo's teaching/evaluation contract.** The plan artifact's
   milestone list retains old week numbers that conflict with its own test
   table. The code's standing rule is development on teaching data only; held-out
   evaluation remains test-harness-only.
4. **Separate the landing page's historical status from current evidence.**
   It still says nothing has been built. A native shell and simulated Watch now
   exist, but learning, connected execution, and broad reliability are unproven.
   Public copy should change only to claims supported by reproducible evidence.
5. **Treat the waitlist as interest, not validation.** Earlier Claude responses
   reported private-sharing limits and an empty database. Those old claims were
   not re-tested here. No public-signup or email-delivery test was performed.
   Interviews and paid pilots remain paused, and nothing should be sent.
6. **Measure operating costs before finalizing usage.** Connector-first execution
   can reduce model calls; it does not by itself prove the subscription is
   profitable. Do not invent an allowance or a spending-cap feature to complete
   the page.

The next product improvement is the already-approved skill-review slice:
plain-language trigger, inputs, steps, and editable rules from Watch, followed by
rehearsal. Additional connectors and cosmetic expansion should wait for that
coherent loop.
