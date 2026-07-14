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

**F10-A: close_gaps run on 018_003** (launched 2026-07-14 evening).
- pid: `logs/close_gaps_f10.pid` · log: `logs/close_gaps_f10.log` · row →
  `logs/close_gaps.jsonl` (seed row appended to `logs/semantic_review.jsonl`,
  era `hand_seed`, keyed to live shas)
- expected: one `applied` row for
  `018_003_cascading_archive_tree_with_origin_aware_restore_01` — add-only
  truncation (`microsecond == {0, 0}`) + `Etc/UTC` tests, kill rate not
  dropped, blind gate GREEN, wt_ twin updated, 10 tfim children resynced.
  A `rejected` row = read the detail, likely solver-weak blind → retry once.
- idempotent relaunch (ledger keyed by harness sha):
  `scripts/run_detached.sh logs/close_gaps_f10.log mix run scripts/close_gaps.exs -- --go --only "018_003*"`
- ⚠️ NEVER run close_gaps `--go` UNSCOPED: its dry list shows 6 phantom
  todos (110_004, 100_004, 110_001, 020_004, 104_002, 032_001) — closed BY
  HAND 07-14 (docs/15), so no tool-ledger row matches their current sha.
---

## ⏭️ IMMEDIATE QUEUE (in order; updated 2026-07-14 evening)

1. **Kamil's five decisions** (section below) — they gate Phase 3, T1.1,
   T1.6 (and TD.3 behind it), the nightly timer, and the T2.2 full-pass
   question. Nothing else blocks them.
2. **F10-A** — close 018_003's harness gap. The ONE confirmed T2.2 finding
   the batch fleet did NOT cover (it was the pilot control, not a batch
   member — verified 2026-07-14 evening). One `close_gaps.exs` run +
   cascade; details in the finding below.
3. Ready now, no decision needed, paid: **T2.4** rubric judge over passing
   tasks.
4. **T1.4** template upgrades land WITH the Phase 3 restart, not before.
5. Bigger builds: **TD.1** adapt pairs (deterministic, zero LLM, 249/249
   measured mintable), then the TD.2–TD.4 decisions.

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

**F10 — 018_003 harness gap (T2.2's first live find, hand-verified
2026-07-14): prompt L20 promises `archived_at` is "a `DateTime` in UTC
truncated to the second"; the harness's 9 `archived_at` assertions pin
neither truncation (`microsecond == {0, 0}`) nor `time_zone == "Etc/UTC"` —
an untruncated `DateTime.utc_now()` solver passes the whole suite.**
- F10-A (fix data): **STILL OPEN — do not assume T2.2-T caught it.**
  Verified 2026-07-14 evening: the T2.2-T fleet closed all 89 *batch*
  findings, but 018_003 was the pilot CONTROL, not a batch member — no
  `close_gaps.jsonl` row exists and the harness still greps clean for
  `microsecond`/`Etc/UTC`/`truncate`. Action: seed `close_gaps.exs` with
  this finding (add-only truncation + time-zone pins), then blind gate +
  wt_/tfim cascade. (Its control-row gold_defect does NOT apply: the
  dead-code `ignore/1` exists only in the pre-fix git reconstruction.)
- F10-B (gate generator): the class belongs to T1.4's harness checklist
  (per-promise coverage); reference this finding there as evidence.

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

*(empty — T3.1 was the only item; the next training-side item lands here
when a training run is planned.)*

### Data extension (docs/13 §2 — build order after Tier 1)

**TD.1 — `:adapt` registry entry + runner (adaptation pairs).** RED-gate
measured 2026-07-13: **249/249 pairs mintable** (`logs/adapt_redgate.jsonl`).
Deterministic, zero LLM. Design: docs/13 §2.1.
**TD.2 — Multi-turn repair-dialogue exporter** (86 chains, PERISHABLE — snapshot
`logs/attempts/` before any big run; archive from 2026-07-12 exists). docs/13 §2.2.
**TD.3 — dedoc** (blocked on T1.6 Dialyzer). docs/13 §2.3.
**TD.4 — style-repair pairs (207) + cap lifts (~1,900 free tfim)** — decide
against docs/16 §4's advisory weights (test_fim already down-weighted to
0.25; a cap lift adds volume in the most-discounted shape). docs/13 §2.4–2.5.

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
4. **T1.6 Dialyzer** — one `mix.exs` + lockfile change. (Two more live
   would-have-caught cases from today's T2.2 batch: 038_001's undocumented
   `duplicate_ids` return violating its own @spec; 043_001's named-table
   atom vs declared `:ets.tid()` type.)
5. **T2.2 full-pass decision** — the 60-root batch says 88% of roots carry
   ≥1 confirmed finding (~1.5/root → ~490 corpus-wide). All 89 batch
   findings are already FIXED (T2.2-T closed 07-14 — docs/15).
   RECOMMENDATION: do NOT pay the remaining ~272-root review (~16M
   tokens) — the classes are known and dominated by promise-coverage debt;
   spend instead on T1.4's checklist, and re-review a small sample AFTER it
   lands to verify the class is closed.

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
