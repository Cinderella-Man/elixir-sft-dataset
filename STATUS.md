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

| what | pid | log | expected result |
|---|---|---|---|
| T1.2 freshness re-screen sweep: `screen_blind_solve --only <54 roots> --rescreen` (launched 2026-07-13 ~18:5x) | **2345136** | `logs/rescreen_freshness_20260713.log` | 54 sha-stamped rows appended to `logs/screen_blind.jsonl` (47 roots whose blind verdicts predate their current harness — mostly the 07-09 R10 harness campaign — plus 7 S6 coverage holes incl. 018_003). REDs already visible in the log (001_004, 002_001, …) → triage queue below. Monitor armed in-session. Relaunch after any death: same command WITHOUT `--rescreen` (the sha-stamped ledger then skips finished rows). |

---

## ⏭️ IMMEDIATE QUEUE (in order, when the sweep exits)

1. **Finish T1.2:** read `logs/rescreen_freshness_20260713.log`; hand-verify +
   triage every RED (judge verdicts are hypotheses — docs/14 rule 10; expect a
   mix of solver slips and possibly new 101_002-class prompt gaps); fix any
   real gaps (prompt edit → wt_/bugfix resync → re-screen); then
   `mix run scripts/check_screen_freshness.exs` must print `stale=0`; then
   wire the checker into CI (`.github/workflows/validate.yml`) + pre-push
   (`.githooks/pre-push`); re-run `--self-test` (engages once sha-stamped rows
   exist); commit ledgers + wiring.
2. **Batch-commit** the sweep's ledger rows (tracked: `logs/screen_blind.jsonl`,
   `logs/screen_triage.jsonl`).

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

**F2 — blind-screen evidence silently staled by harness edits.**
- F2-A (fix data): 54-root re-screen sweep **RUNNING** (see above) + RED
  triage when it exits.
- F2-B (gate generator): harness-sha stamping DONE; **CI + pre-push wiring
  PENDING** (lands the moment the gate reads `stale=0`).

**F3 — permanent reject rows survived their gate's repair (15 unsound found).**
- F3-A (fix data): DONE → docs/15 (rows purged, 9 blocked units minted).
- F3-B (gate generator): **T1.7 gate-sha-keyed reject rows — TODO** (+ T3.2
  weekly reverify sample as backstop).

**F5 — generation-process chatter comments shipped in 11 files.**
- F5-A (fix data): `# Prompt:` class DONE → docs/15; **`--- added:` banner
  class in the 13 previously-strengthened families — TODO** (reword + resync;
  NOTE: changes harness shas → those families need freshness re-screens, do
  it in one batch WITH F2-A's triage).
- F5-B (gate generator): **T1.8 chatter-lint extension — TODO.**

**F7 — environmental failures written as screen VERDICTS (found live during
the F2-A sweep).**
- F7-A (fix data): 017_001's fresh RED row says "Postgres … not reachable at
  127.0.0.1:5432" — an environment fact, not a prompt verdict. After the
  sweep: annotate via a triage row (entailed/environmental) so it never enters
  the prompt-gap queue; same for any other env-dependent RED the sweep writes.
- F7-B (gate generator): `screen_blind_solve.exs` must classify
  environment-unreachable grades as `green: nil` + `error: environmental`
  (exactly like transport errors — "not a verdict on the prompt"), so no
  future run can ledger an environmental RED. TODO after the sweep exits
  (the running sweep uses its already-loaded copy).

*(F4 — tools imitating grandfathered anti-patterns — and F6 — LLM-judge
hallucinated verdict — closed 2026-07-13, both tiers done: docs/15.)*

**Pre-triage notes for the F2-A RED queue (hand verdicts to cross-check the
judge against, rule 10):** 005_003 = ENTAILED/keep (prompt says "older than"
3×; the test pins exactly that inclusive-at-TTL boundary; solver dropped at
`>=`). 001_004 (candidate badmatch crash), 002_001 (candidate typespec
compile error), 015_003 (candidate calls its own never-started named
supervisor) — solver-slip signatures, confirm at triage.

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

**T1.2 — S6 freshness gate: blind evidence must match the CURRENT harness.
[IN PROGRESS — checker built + self-tested; screen rows now sha-stamped;
backlog sweep RUNNING (see above); REMAINING: triage sweep REDs → `stale=0`
→ wire into CI + pre-push]**
- WHY: `logs/screen_blind.jsonl` was keyed by PROMPT sha only, but blind
  solvability is a property of the (prompt, harness) PAIR — a harness edit
  silently invalidated the evidence (hit live on 013_001).
- WHAT/HOW: `scripts/check_screen_freshness.exs` (gate + `--self-test`);
  fresh = sha-stamped row, or strengthen-success row for that exact harness,
  or legacy row newer than the harness's last git commit.

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

**T1.5 — Extend the semantic-mutant operator set. [FREE, CPU sweep after]**
- WHY: the S8 floor is only as sharp as its operators (today: comparison swap,
  ±1 on literals, :ok↔:error, bool flip). Sharper operators = better
  tightness measurement AND more `bugfix_` units minted automatically.
- WHAT: guard-boundary swaps (`min`↔`max`), range endpoints (`a..b`), clause
  reordering, arithmetic swaps (`+`↔`-`, `*`↔`div`).
- HOW: `lib/gen_task/mutation.ex` (`semantic_mutants_textual/2` + the AST
  measurement twin stay in step), tests, corpus re-measure sweep. Expect new
  below-floor families — classify + fuzz survivors BEFORE calling them work
  (docs/14 rules 7 and 11).

**T1.6 — Dialyzer gate over the golds. [NEEDS KAMIL: one mix.exs/lockfile
change; then FREE (PLT build + weekly CI)]**
- WHY: 019_001 shipped a `@spec` contradicting its own code; specs must be
  machine-checked. Hard prerequisite for the dedoc shape (docs/13 §2.3, ~331
  free units) — wrong specs must never become training targets.
- WHAT/HOW: add `dialyxir`, one-time PLT, driver staging each gold with its
  deps, weekly CI gate. Pilot on 5 families first. Design: docs/13 §2.6.

**T1.7 — Gate-sha keying for permanent reject ledgers. [FREE] (Tier B of the
unsound-reject finding)**
- WHY: 15 unsound `102_001` tfim reject rows sat for 2 days because verdicts
  written by a broken gate survived the gate's repair — the 074_x class,
  RECURRED. The repo's own rule 1 ("a ledger without a content key rots
  silently") was applied to the data but never to the GATE'S OWN CODE.
- WHAT: every permanent-reject row also records `gate_sha` — the content sha
  of the module(s) that produced the verdict (`test_fim.ex`, `bugfix.ex`,
  `mutation.ex` as appropriate). Readers treat a row whose `gate_sha` no
  longer matches the compiled module as RE-OPENABLE (exactly how a changed
  harness sha already re-opens bugfix rejects). A gate repair then
  auto-invalidates its old verdicts instead of relying on someone remembering
  to audit.
- HOW: the `record_rejected` sites + `rejected_labels`-style readers in
  `lib/gen_task/{test_fim,bugfix}.ex` (+ fim's ledger); legacy rows without
  `gate_sha` stay valid until the next `reverify_rejects.exs` pass clears
  them; T3.2's weekly reverify sample is the backstop. Tests + registry
  counts must stay honest (`missing/2` sees re-opened units).

**T1.8 — Extend the chatter lint to generation-process meta-comments. [FREE]
(Tier B of the `# Prompt:` finding)**
- WHY: the strengthener shipped `# Prompt: "…"` citation comments into 11
  files — S10-class process chatter in a register no hand-written harness
  uses. Caught by Kamil's eye, not by any gate. The S10 sweep's markers
  (emoji, `# FIX`, "Wait,") never covered citation-style comments.
- WHAT: the accept-gate chatter lint also flags comments that cite the
  generation process rather than describe behavior: `# Prompt:`,
  `# The prompt says`, `# --- added:`-style banners. Tier A: sweep the 13
  previously-strengthened families for the `--- added:` banner class and
  reword (deterministic edits + tfim/wt resyncs — comments live outside
  carved test blocks).
- HOW: extend the detectors in the Evaluator lint set (`quality_shortfall`)
  + `--self-test` with a planted comment; corpus grep proves 0 instances
  after the Tier A sweep.

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

**T2.3 — Second-source the 15 "FAIL, triaged entailed" keeps. [~15 calls]**
- WHY: each rests on a single triage verdict, and a judge verdict was proven
  WRONG on 2026-07-13 (101_003 — docs/14 rule 10). One more independent blind
  solve per keep either flips it GREEN or confirms solver-weak with two
  sources.
- HOW: `screen_blind_solve --only <the 15> --rescreen`; triage new signal.

**T2.4 — Rubric LLM-judge pass over PASSING tasks (sampled). [PAID; round-#2
candidate]** — WHY: our judge only ever sees failures; judge filtering adds
quality beyond execution filtering (docs/12 §6.4). HOW: 3-axis rubric on a
stratified sample, agreement-logged second judge family (PoLL) — rule 10
showed single-judge bias is real.

**T2.5 — Randomized ExUnit seed sweep. [FREE]** — WHY: eval seed pinned to 0;
order-dependence bugs invisible (docs/12 §5.4). HOW: occasional sweep variant
with random seeds; low expected yield, cheap.

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

**T3.2 — Make the scrutiny tools standing: wire `spot_verify.sh` (sampled
accept-side re-verification) + a `reverify_rejects.exs` sample into weekly
CI. [FREE]** — WHY: they found 15 unsound reject rows and re-confirmed 204
accepted dirs on 2026-07-13; as one-shots they rot — as CI they catch gate
regressions the day they happen.

**T3.3 — Small tools with real quality effect. [FREE]** — (a) promote the
077_001 public-API survivor fuzz into `scripts/fuzz_survivors.exs` (the
verification layer behind every at-ceiling claim — docs/14 rule 11); (b) the
screen's `first_failure` should unwrap `{:invalid, %ExUnit.TestModule{}}`
setup_all errors (102_003's diagnosis needed a local re-grade).

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
   mutants; measured, closed — see docs/15).
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
