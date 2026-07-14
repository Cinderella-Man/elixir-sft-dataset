# PROJECT STATUS — the live work list (read after CONTEXT.md's HOW-WE-WORK rules)

**HARD RULE (CONTEXT.md rule 5): this file contains ONLY todo / in-progress /
blocked items — NOTHING that is done.** Completed work moves immediately to
`docs/15-completed-work-log.md` (and lives in git history). The point of this
file is to find all the things that need work, at a glance. Update it AS YOU
GO — before launching a job, after finishing one — never "at the end".

Reference docs: `docs/14` (full handover: gates, tools, ledgers, runbooks),
`docs/12` (quality standard S1–S12), `docs/13` (data-extension designs).

---

## ▶️ RUNNING RIGHT NOW

**Nothing.** (T2.7 residue 100_004 closed 2026-07-14 morning — docs/15.) Plan: add-only harness tests — (1) independent RFC 6238
reference computation (base32 decode + HMAC-SHA1 + dynamic truncation are all
verbatim in the prompt) swept over 300 steps, (2) secret-shape test (160 bits
= 32 unpadded base32 chars, documented), (3) window-default=1 probe (base±2
codes rejected without a :window option). Expected: kills all 19 arithmetic
survivors; the 4 guard-widening mutants in decode_char (65→64, 90→91, 50→49,
55→56 on the `char in ?A..?Z` / `?2..?7` guards) are unreachable through the
documented API (the vault only ever decodes its own valid secrets) → honest
internals ceiling 36/40 = 0.90. Then: perfect gate, format, mutants, semantic
re-measure + survivor classification, wt_/tfim cascade, blind re-screen
(detached), mint any new carves.
---

## ⏭️ IMMEDIATE QUEUE (in order; updated 2026-07-14 morning)

1. **Kamil's four decisions** (section below) — they gate Phase 3, T1.1,
   T1.6 (and TD.3 behind it), and the nightly timer. Nothing else blocks them.
2. Ready now, no decision needed: **T2.1** S9 debt — design the re-carve
   path FIRST (docs/14 §5.0b caveat), then the 11 reach-in families.
3. Paid review passes once 2 is drained: **T2.2** scaled semantic review
   (stratified 60-root batch, then decide on full), **T2.4** rubric judge
   over passing tasks.
4. **T1.4** template upgrades land WITH the Phase 3 restart, not before.
5. Bigger builds: **TD.1** adapt pairs (deterministic, zero LLM, 249/249
   measured mintable), **T3.1** export contract (MANDATORY before any
   training run), then the TD.2–TD.4 decisions.

*(T1.5 closed 07-13; T2.3 + T2.5 + all of T2.7 incl. the 100_004 residue
closed 07-14 — docs/15.)*

## 📋 QUALITY TODO REGISTER (2026-07-13 — why / what / how / cost per item)

An item leaves this list only when done (→ docs/15) or when Kamil kills it.
"FREE" = CPU/engineering only, no API calls.

**HARD RULES (CONTEXT.md rules 7–10):** every finding = **TWO EXPLICIT
TASKS** (Task A: fix the existing data; Task B: gate the generator so it can
never recur) — the problem leaves STATUS only when BOTH are done; spot-checks
run on accepted AND rejected data; every full-dataset run gets a
detail-reviewed pilot first; every solved item is removed from here and
committed immediately (one solved item = one commit).

### 🔎 OPEN FINDINGS — two tasks each

**F1 — repaired accepts shipped prompt↔harness gaps (6 found live).**
- F1-A (fix data): DONE → docs/15 (6 prompts fixed, cascaded, re-screened GREEN).
- F1-B (gate generator): **T1.1 accept-time blind re-screen in the loop —
  PENDING KAMIL'S SIGN-OFF.**

*(Closed with both tiers done — see docs/15: F2 — blind evidence staled by
harness edits; F3 — reject rows surviving their gate's repair; F4 — tools imitating grandfathered anti-patterns; F5 —
generation-process chatter; F6 — LLM-judge hallucinated verdict; F7 —
environmental failures as verdicts.)*

### Tier 1 — make every FUTURE generated unit better (loop + gates)

**T1.1 — Wire the §5.2 blind re-screen into the generation loop.
[NEEDS KAMIL'S SIGN-OFF on the policy; build ~half a day; runtime ~1 solver
call per repaired accept]**
- WHY: a base/variation accepted after ≥1 repair was fixed by a model that SAW
  the harness failure report, so acceptance proves nothing about the prompt
  alone. Not theoretical: 6 of the 22 retro-screened repaired accepts had
  shipped harnesses asserting things their prompts never said (101_002,
  102_002/3/4, 626_004, 101_003 — all found+fixed 2026-07-13, see docs/15).
- WHAT: in the loop, any base/variation accepted with `attempts > 1` gets one
  independent blind re-solve (prompt only) before promotion; RED → quarantine
  for triage, never silent promotion. Plus docs/12 §5.2.2: an entailment judge
  over the harness DIFF made during repair.
- HOW: post-accept hook in the accept path reusing the `screen_blind_solve`
  mechanism + ledger; behind `GEN_BLIND_RESCREEN=1`; CI later refuses accepts
  lacking the evidence row. Design sketch: docs/12 §5.2.1.

**T1.4 — Phase 3 template upgrades (docs/12 §5.3 — designed, never landed).
[FREE, forward-only; land WITH Phase 3, not before]**
- WHY: measured monoculture — 76% of seed prompts open "Write me", one frozen
  few-shot exemplar (root cause of the GenServer monoculture), ZERO doctests
  corpus-wide (26 golds carry `iex>` examples that never execute), harness
  checklists designed in docs/10 §3.4 but never landed.
- WHAT: (a) shared harness-rule constant (≥1 negative/error-path test per
  public function, boundary tests, `describe` grouping, OTP conventions) used
  by base/variation/write-test templates — triplicated today, drifted once
  already; (b) request doctests + one property test where apt; (c) rotate 3–5
  few-shot exemplars of different shapes; (d) record each seed's blind-screen
  outcome as free difficulty metadata.
- HOW: all in `lib/gen_task/prompts.ex`; rationale in docs/12 §5.3.


**T1.6 — Dialyzer gate over the golds. [NEEDS KAMIL: one mix.exs/lockfile
change; then FREE (PLT build + weekly CI)]**
- WHY: 019_001 shipped a `@spec` contradicting its own code; specs must be
  machine-checked. Hard prerequisite for the dedoc shape (docs/13 §2.3, ~331
  free units) — wrong specs must never become training targets.
- WHAT/HOW: add `dialyxir`, one-time PLT, driver staging each gold with its
  deps, weekly CI gate. Pilot on 5 families first. Design: docs/13 §2.6.


### Tier 2 — raise EXISTING corpus quality (evidence says more is there)

**T2.1 — Clear the S9 grandfathered debt: 52 harnesses with `:sys.get_state`
reach-ins (11 April-era families), 142 with `Process.sleep`. [~2 calls/family
where LLM-assisted; some hand work]**
- WHY: proven 2026-07-13 that it actively corrupts future work — the
  strengthener imitated the existing reach-ins on 101_001 three times.
  Reach-in tests are also weaker tests.
- WHAT: ledgered rewrite tool in the strengthen mold (observable-behavior
  equivalents; blind gate; restore-on-failure).
- HOW: CAUTION — modifying existing test blocks orphans their carved tfim
  golds (the add-only rule exists for this); the tool needs the re-carve path
  (docs/14 §5.0b caveat). Start with the 11 reach-in families; sleeps only on
  flake-ledger evidence (docs/12 §4.2.6).

**T2.2 — Scaled semantic review. [PAID: ~3.5M tokens for a stratified 60-root
batch; full ~330 roots ≈ 20M]**
- WHY: the 11-dir pilot found 2 real gold defects (018_003, 101_002); the
  corpus-wide defect rate is unknown.
- HOW: stratified by era, adversarially verified findings only, small-batch
  ledger protocol; then decide whether the full pass pays.

**T2.4 — Rubric LLM-judge pass over PASSING tasks (sampled). [PAID; round-#2
candidate]** — WHY: our judge only ever sees failures; judge filtering adds
quality beyond execution filtering (docs/12 §6.4). HOW: 3-axis rubric on a
stratified sample, agreement-logged second judge family (PoLL) — rule 10
showed single-judge bias is real.



**T2.6 — Prompt-register monotony rewrite (improvement round #2 — do NOT
start before steady state). [BIG: 2,396 tfim + 302 wt_ + 80/332 seed openers;
own tool + ledger + blind re-screen budget]** — docs/12 §7.4;
frozen-template overfitting is a documented SFT failure mode.

### Tier 3 — protect the TRAINING side

**T3.1 — Export contract + family-keyed split + round-trip validator.
[MANDATORY before any training run; FREE to build]** — WHY: 91.7%
within-family text overlap BY CONSTRUCTION — a naive random split leaks
train→val and invalidates every eval. HOW: docs/13 §3.1 (per-shape spec,
FIM-as-chat decision, family-keyed splits, dedup/sampling weights, CI-gated
round-trip validation).



### Data extension (docs/13 §2 — build order after Tier 1)

**TD.1 — `:adapt` registry entry + runner (adaptation pairs).** RED-gate
measured 2026-07-13: **249/249 pairs mintable** (`logs/adapt_redgate.jsonl`).
Deterministic, zero LLM. Design: docs/13 §2.1.
**TD.2 — Multi-turn repair-dialogue exporter** (86 chains, PERISHABLE — snapshot
`logs/attempts/` before any big run; archive from 2026-07-12 exists). docs/13 §2.2.
**TD.3 — dedoc** (blocked on T1.6 Dialyzer). docs/13 §2.3.
**TD.4 — style-repair pairs (207) + cap lifts (~1,900 free tfim)** — decide
together with T3.1's weighting. docs/13 §2.4–2.5.

---

## 🧍 WAITING ON KAMIL (decisions only — nothing else blocks Phase 3)

1. **T1.1 / §5.2 sign-off** — wire the accept-time blind re-screen into the
   loop (evidence: 6 gaps in 22 repaired accepts).
2. **docs/12 §4.2 sign-offs** — spot-review scope, prompt-monotony scope;
   the semantic-floor half is answered (floor = kill rate among OBSERVABLE
   mutants; measured, closed — see docs/15). Note S8 now has the complete
   three-way survivor framework to sign off against: killable / internals /
   **spec-ceiling** (observable but unpinnable-by-spec — docs/13 §1.5.1b,
   born from 037_001).
3. **Nightly-sweep systemd timer install** — 4 commands, docs/12 §4.1.10.
4. **T1.6 Dialyzer** — one `mix.exs` + lockfile change.

## Current mode: 🔧 CATCHING UP (improvement round #1, 2026-07)

New base generation is **paused**. Remaining exit conditions for this round:

- [ ] §4.2 / §5.2 decisions signed off (above)
- [ ] Phase 3: new generation resumed (490 queued bases) and first batch
      validated clean under the full gate suite
- [ ] The line drawn (docs/12 §7.2): delete catch-up tooling
      (`resync_embeds.exs`, `rescreen_repaired.exs`, `strengthen_harnesses.exs`,
      `enrich_prompts.exs`, `quality_chain*.sh`, `reverify_rejects.exs` et al.
      per the §7.2 table), remove the backfill vocabulary, flip this file to
      STEADY STATE

Everything previously listed as done in this round: `docs/15-completed-work-log.md`.

## The two modes (definitions)

**STEADY STATE** — one command produces new data
(`scripts/run_detached.sh logs/loop.log mix run scripts/generate.exs`), every
quality check lives inside that loop or in CI, and nothing needs to be "caught
up". No backfill tooling exists in the repository.

**CATCHING UP (improvement round #N)** — we raised the quality standard, so
existing data must be brought up to it. Protocol: docs/12 §7.3 (bump standard
→ wire check into loop+CI FIRST → one-shot ledgered upgrade tool → run to
completion → verify whole corpus → delete the tool → flip this file back).

## Round history

| # | Round | Dates | What was raised | Status |
|---|-------|-------|-----------------|--------|
| 1 | 2026-07 QA catch-up | 2026-07-07 → … | prompt↔test consistency, mutation & format gates, embed staleness, blind screening (docs/10) + S6 freshness, reject-ledger audits, semantic floor closed (docs/15) | **in progress** |
