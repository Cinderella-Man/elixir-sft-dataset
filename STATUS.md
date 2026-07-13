# PROJECT STATUS — read this first

This file is the single place that says what the project is doing **right now**.
It answers one question: are we **producing new data**, or are we **catching up**
on a quality improvement? Update it whenever the answer changes; everything else
(docs, scripts, plans) is secondary to this file.

---

## Current mode: 🔧 CATCHING UP

**Improvement round #1 — the 2026-07 quality-assurance catch-up.**
New base-task generation is **paused**. The plan of record is
`docs/11-catch-up-plan.md` (phases) + `docs/12-quality-standard-and-steady-state.md`
(the concrete work list, the quality standard, and the exit protocol).

What that means in practice:

- **Allowed now:** deterministic corpus fixes, gate hardening, validation sweeps,
  the scope decisions listed in docs/12 §4.
- **Next (Phase 2):** one derivative top-up run
  (`GEN_ONLY=backfill scripts/run_detached.sh logs/backfill.log mix run scripts/generate.exs`)
  — only when docs/12 §4 items marked **[blocks Phase 2]** are done.
- **Then (Phase 3):** new base generation (490 queued ideas) — only when Phase 2
  is complete and the loop-hardening items marked **[blocks Phase 3]** are done.
- **Then: draw the line** (docs/12 §7): delete the catch-up tooling and the
  backfill vocabulary, and flip this file to STEADY STATE.

### Checklist to exit this round

- [x] Stale child-prompt copies resynced + staleness gate wired (docs/11 §1a, 2026-07-10)
- [x] Seed self-check fixed, 50 blocked units freed (docs/11 §1b, 2026-07-10)
- [x] Corpus format gate green again (23 embeds, 2026-07-10)
- [ ] docs/12 §4.1 deterministic punch list — DONE 2026-07-10: 020_001 rebuild
      (re-screen GREEN), 001_002 reach-in, chatter sweep (4 families), fence
      artifacts, 23-tfim re-gate (0/23), repair audit (0 flags), semantic
      re-measure (tail = 20 <0.5), register metric, backfill-script removal;
      001_004 redesign (re-screen GREEN), §4.1.3 per-fn+init/1 sweep (ZERO
      survivors across 1,612 evals — populations #1/#2 closed empty);
      §4.1.9 decontamination gate (0 exact / 0 near-miss vs 786 benchmark
      rows); STAGED: nightly-sweep systemd units (needs install, §4.1.10).
      **§4.1 is COMPLETE** except the staged timer install.
      **Every [blocks Phase 2] item is now done — Phase 2 top-up is ready to
      launch on Kamil's go (paid run).**
- [x] docs/12 §4.2.1 — 099_002/3/4 screened GREEN; S6 holds for all 303 seeds (2026-07-10)
- [ ] docs/12 §4.2 decisions signed off (spot-review scope, prompt-monotony scope, semantic floor — tail confirmed at 20 families <0.5 by re-measure)
- [x] docs/12 §5 loop hardening §5.1 — ALL DONE (items 1–7 2026-07-10; item 8
      gate + classification 2026-07-11; remediation + CI wiring 2026-07-12:
      **embed check 1266 clean / 0 reflow / 0 drift, gated in CI**). Still
      OPEN: §5.2 decision (accept-time blind screen for repaired bases +
      entailment judge) — needed before Phase 3
- [x] **Phase 2 COMPLETE 2026-07-12 ~23:0x** — `work_status --counts`:
      variations 0/83, fim 0/331, write_test 0/331, test_fim 0/331 pending.
      Original entry: derivative top-up run **LAUNCHED 2026-07-10 ~18:45** (detached,
      `logs/backfill_phase2.log`; 111 seeds / 710 units). Three passes done by
      2026-07-12 (details in "Where we are right now"). After the two
      registry-honesty fixes (phantom-326 tfim, pool-capped fim) the honest
      remainder is: **10 winnable units running now** (7 fim + 3 variation,
      relaunched 2026-07-12 with GEN_EXCLUDE_SEEDS), **12 bundle-fim units +
      4 variation units parked behind the queued triage decisions**. Phase 2
      closes when the winnable run finishes AND Kamil rules on decisions 1–3
      (each either deletes its parked units from the registry or schedules the
      fix that makes them producible)
- [x] **2026-07-12 spot-check findings RESOLVED** (~18:45: all four content
      fixes landed, resynced, re-gated; both systemic lints live; post-run
      pass executed in full — see below). Original entry: (random
      11-dir semantic review, every finding adversarially verified — Kamil:
      "resolved BEFORE we progress to new generation"):
      1. `018_003_..._01` gold carries a deliberately warning-silenced
         dead-code block + no-op `ignore/1` helper (`solution.ex:243-245,277`)
         — the model gamed the house-style gate. Hand-fix gold, re-gate
         family, resync children embeds (2 fim + wt + 10 tfim).
      2. `101_002_..._01` harness asserts `tracked_key_count/1` (never in the
         prompt — a prompt-only solver crashes) and depends on undocumented
         `:max_window_ms`. Fix the prompt, resync children (wt + 10 tfim),
         audit WHY the blind screen passed this family.
      3. `019_001_..._01` `@spec bulk_create_items` contradicts @doc and code
         (map vs tuples) — fix spec, resync children (3 fim + 10 tfim).
      4. Misleading test name "members exactly at the window boundary are
         counted" (tests 1 ms inside) in 101_002's harness + wt copy — it is
         literally the spec of tfim_101_002_08. Rename in parent + wt,
         resync.
      5. **Systemic — DONE 2026-07-12 evening:** (a) corpus-wide scan with
         the same detectors over all 4,605 dirs (`logs/spotcheck_scan.jsonl`):
         both classes fully contained to the two families above — zero other
         instances; (b) both detectors are HARD accept-gate lints now
         (`Evaluator.no_op_helpers/1`, `undocumented_api_calls/3`, wired into
         `quality_shortfall`, 288 tests green), so neither class can recur.
      **Progress:** items 1–4 hand-edits are committed; family re-gating
      (perfect + mutants) and embed resyncs run the moment the loop exits
      (resync refuses while a generate BEAM is alive).

      ### POST-RUN PASS — EXECUTED 2026-07-12 ~18:20-18:45 ✓ (all six steps;
      ### one extra find en route: tfim_072_004_03's carved test head at 100
      ### columns — renamed + the mint gate now enforces ≤98 on carved
      ### fragments at accept time. Remainder loop relaunched: 3 variations +
      ### 5 fim + 13 macro tfim.) Original checklist:

      1. **Purge `074_*` entries from `logs/tfim_rejected.jsonl`** — the
         running loop's in-memory OLD isolation gate rejected the macro-
         asserting tfim blocks as "vacuous" (11 on 074_001, 10 on 074_002,
         likely more on 074_004) and permanently ledgered them. The gate is
         fixed on disk (errored-kills now count); the verdicts are unsound.
         Purge by prefix AFTER the loop exits (it appends while running).
      2. **Embed resyncs for the four hand-edited spot-check families**
         (018_003, 019_001, 101_002, wt_101_002): `resync_embeds.exs`
         (module-FIM/wt_ from the edited parents) + `resync_tfim_embeds.exs
         --apply` (module fences changed), then both dry-runs must converge.
      3. **Re-gate the four edited families**: validate perfect + mutants
         (hand edits require the perfect eval, docs/12 §5.1.9).
      4. Corpus gates: `format_corpus --check`, `check_embeds` (expect 0
         reflow / 0 drift).
      5. Batch-commit remaining accepted dirs + push (pre-push validates).
      6. **Relaunch** `GEN_ONLY=backfill` — picks up: 034_001 variations with
         named-warning repairs, re-mint of the purged 074 macro tfim blocks
         through the fixed gate, and any remaining tail. **Blind-screen audit
      answered:** 101_002 has NO screen ledger entry; it was accepted with
      `variation_blind=True`, and the repair loop defeated blindness — the
      failure report leaks harness internals (missing-function errors), which
      the fix reply then satisfies. This is the first confirmed live instance
      of the open §5.2 gap ("accept-time blind screen for repaired bases"),
      turning that decision from theoretical to demonstrated. §5.2 stays the
      remaining pre-Phase-3 design decision.
- [ ] Phase 3: new generation resumed and first batch validated
- [ ] The line: catch-up tooling deleted per docs/12 §7.2, this file flipped

### Where we are right now (2026-07-12 ~23:15 — PHASE 2 EXECUTION COMPLETE)

**`work_status --counts`: 0 pending across every work type** (variations 0/83,
fim 0/331, write_test 0/331, test_fim 0/331). All four queued decisions were
resolved as FIXED and proven live; the spot-check blockers are resolved with
both defect classes contained and gated; five loop-level information/gate gaps
found and fixed during the runs (bundle prompts, manifest staging, repair
clobbering, named warnings, predicate-name regex; isolation errored-kills).

### Existing-data quality backlog (2026-07-12 evening — Kamil: "assure the
### best quality of already existing data"; tools built, runs on his go)

1. **Retroactive blind screen of repaired accepts** — TOOL READY:
   `mix run scripts/rescreen_repaired.exs` (dry) / `-- --go` (paid) /
   `-- --report`. Population: 74 of 126 accepted variations were accepted
   after ≥1 repair (blind property unverified — the §5.2 gap, 101_002 the
   proven hit). Ledger cross-check shows the REAL remainder: 42 already PASS
   for their current prompts, 10 FAIL-but-triaged-entailed (solver errors,
   prompts explicitly sufficient — kept), **22 never screened ≈ 22 solver
   calls**. Reuses the S6 screen + its ledger; resume-free.
2. **Semantic-mutant floor remediation** — TOOL READY:
   `mix run scripts/strengthen_harnesses.exs` (dry) / `-- --go [--limit N]`.
   30 deduped parent families below 0.5 kill rate (worst: 075_004 at 0.00).
   Per family: one ADD-ONLY strengthen call + hard gates (existing test
   blocks byte-verbatim — tfim golds carve them; reference green + zero
   warnings + lints; whole-mutant killed; semantic re-measure ≥ 0.5 and
   ≥ old; **blind gate: a prompt-only solve must pass the stronger harness**)
   then apply + wt_ twin + tfim resync with restore-on-failure. ~2 LLM
   calls/family. New tests become new carvable tfim units automatically.
3. **Dialyzer over the golds** (free, unpiloted): would have caught the
   019_001 @spec lie mechanically. Pilot parked; needs a PLT build + a
   driver staging each gold with its deps.
4. **Scaled semantic review** (the expensive one): today's 11-dir
   review+verify workflow cost ~660k subagent tokens and found 2 defective
   families. All ~330 roots ≈ 20M tokens; a stratified 60-root batch
   (≈3.5M) would tighten the defect-rate estimate first.
5. **Full --fim sweep** — DONE 2026-07-12: ALL FIM TARGETS EXERCISED ✓
   (first sweep since the day's ~40 new fim units; CI runs it weekly).

### Semantic floor — POINT 2 COMPLETE (2026-07-13, docs/13 §1.4–§1.5.2)

**13 of the 20 tail families now clear the floor** (mean +0.37; 074_001/079_001/
075_001 at 1.00). The recipe that worked, and is now the documented remediation
order: **enrich the prompt → canonical blind re-screen → re-strengthen the
harness** (`enrich_prompts.exs` → `screen_blind_solve.exs` →
`strengthen_harnesses.exs`, all ledgered/resumable). Nine families were only
strengthenable after enrichment; four had been impossible before it. Clinching
evidence: 001_001's prompt FAILED the blind screen in July; enriched (22→109
lines) it passes, and its harness went 0.47 → 0.87.

**The 7 that remain are classified, not hand-waved** (`classify_survivors.exs`):
3 are AT THEIR OBSERVABLE CEILING (041_001, 041_003, 023_002 — surviving mutants
change only internals; killing them would need the `:sys.get_state` reach-in the
S9 lint forbids, which is exactly what each attempt tried) and 4 are real gaps
with named next steps (063_004 zero-budget semantics; 101_001 free retry;
013_001 tests its own reference fails; 077_001 hardest, 0.42).

**Conceptual result for §4.2/S8:** a flat 0.5 floor is NOT universally reachable.
The honest metric is the kill rate among OBSERVABLE mutants, with the rest a
documented ceiling. Classify survivors before calling a family "work".

**Six bugs fixed en route** (see docs/13 §1.5.2), incl. 51 stale `wt_` dirs —
3 shipping a stale GOLD harness — now gated in CI + pre-push.

### Bugfix corpus MINTED — 2026-07-13 ~01:00 ✓

**957 byte-surgical bug→fix units across 326 seeds; registry converged to
bugfix 0 pending** (three passes; final 2 candidates correctly rejected as
survivors and ledgered). Every unit: task spec + one-line semantic bug with
comments intact + the real failing ExUnit report; gold byte-equal to the
parent reference. Kamil's two spot checks shaped the pipeline: the reject
audit (all verdicts cross-match the independent survivor measurements; ledger
now keys on solution+harness sha so strengthened harnesses re-open survivors)
and the accept audit (caught AST-reprint pollution → byte-surgical
`semantic_mutants_textual/2`; standing tool `scripts/audit_bugfix.exs` —
**10/10 random real units pass all six properties**). The 28 property-tfim
units minted in the same run. format_corpus knows the shape (bugfix prompts'
buggy fences are captured mutant data, never reformatted — the repair_ rule).
Next per Kamil's overnight brief: `strengthen_harnesses -- --go` (point 2).

### Semantic-floor run COMPLETE — 2026-07-13 ~04:30 (docs/13 §1.4)

`strengthen_harnesses` over all 30 weak-tail families: **10 already_ok** (the
July-8 tail was substantially a MEASUREMENT ARTIFACT — the 0.00–0.35 band was
all wt_ rows whose parents measure fine; zero calls spent), **3 applied and
committed** (002_003 0.40→0.68, 097_002 0.47→0.84, 077_004 0.48→0.52 — each
through add-only + green + lints + whole-mutant + re-measure + BLIND gate,
propagated to wt_/tfim, re-gated perfect+mutants+format), **17 rejected**:
12 by the blind gate, 2 by the S9 lint (the model tried `:sys.get_state` to
cheat mutants), 2 wrote tests the reference fails, 1 stayed below floor.

**The finding that matters (evidence in docs/13 §1.4):** for the 12 blind-gate
families the PROMPT is the weak link, not the harness — they are terse (14–18
lines) with no behavioral specificity, so any tightening test pins something
unstated. Positive control: 097_002's detailed prompt produced the biggest
win. **Work item, in this order:** enrich prompt → blind re-screen → re-
strengthen (all three tools exist; rejected families re-attempt for free).
This also largely closes the §4.2 semantic-floor question with evidence.

### Data extension research — docs/13 (2026-07-12 night; Kamil's deep-research brief)

Full catalog in `docs/13-existing-data-improvement-and-extension.md`. Built and
proven this session: **`:bugfix` work type** (verified bug→fix pairs from
killed semantic mutants — 976 pending units / 326 seeds, zero LLM, registry-
live so fresh generation mints it automatically; pilot 6/6 green) and
**property-block tfim carving** (075_001: 0 → 29 carvable, pilot 10/10
isolation-killed; zero churn on the 3,203 shipped prompts). Repair-mint
manifest fix landed (tier-B pairs re-verifiable). Ready-to-build designs with
measured volumes: adaptation pairs (base gold + variation spec, RED-gate),
multi-turn repair dialogues (86 chains — PERISHABLE, logs/attempts archived
2026-07-12), dedoc (blocked on the Dialyzer gate), style-repair pairs (207),
cap lifts (~1,900 free tfim). **Blocking prerequisite before any training
use: the export contract + family-keyed split (91.7% within-family text
overlap — a random split would leak).**

**What still stands before Phase 3** (unchanged owners):
- **§5.2 decision (Kamil)** — accept-time blind screen for repaired bases;
  101_002 is the confirmed live instance of the gap.
- docs/12 §4.2 sign-offs (Kamil) and the nightly-sweep systemd timer install
  (§4.1.10, Kamil).
Then Phase 3 (490 queued base ideas) and, after its first validated batch,
"the line" (docs/12 §7.2: delete catch-up tooling, flip this file).

---

### Earlier today (2026-07-12 ~13:00 — push unblocked, Phase 2 tail triaged, focused relaunch)

**The failed `git push` is fixed and explained.** Two separate things looked like
"hundreds of problems" but were not corpus rot:

1. **The actual push blocker** was the corpus format gate: 218 prompt embeds
   (216 from the 2026-07-12 resync) carried a trailing blank line inside the
   fence. Canonicalized corpus-wide, root cause fixed in
   `EvalTask.Fim.rewrite_skeleton` (trims the skeleton's trailing newline), and
   `format_corpus --check` now says it is a gate instead of "report only".
   Both embed gates re-verified after formatting: 1269 clean / 0 reflow /
   0 drift, tfim resync unchanged.
2. **The "hundreds of warnings"** were unused-alias noise from the raise-body
   MUTANTS the `--mutants` gate compiles on purpose (broken by design), spilling
   to the terminal because ParallelCompiler workers print to stderr no matter
   what. Reference solutions were already warning-free (the perfect gate
   enforces zero). The spill is now captured (`EvalTask.Runner.quiet_compile`),
   verified: a planted unused-alias mutant grades `compile_warnings=1` with
   0 stderr bytes. Found en route: all five bare-`elixir` scripts let a stale
   `_build/test` beam shadow freshly-compiled dev code — path order fixed.

**Full perfect sweep re-run (logs/perfect_sweep_20260712.log): 6 failures → 0
real ones.** 034_001_03 + 089_004_04 (from the 12 hand-fixed golds — the
hand-fix left stale skeletons; the embed gate can't catch that, the perfect
eval can) rebuilt deterministically and re-graded 1.0; three tfim fragments
carried >98-char carved test heads — test names shortened in parent+child, all
30 sibling tfim prompts resynced. 017_001 fails only without a Postgres host
(environmental, expected unattended).

**Phase 2 tail triaged deterministically (zero LLM calls).** The registry said
7 variation + 32 fim units. A viable-target sweep over all pending seeds showed:

- **13 fim units could NEVER be produced** — parents with 1-2 unique functions
  already covered (063_001, 075_004, 092_001/2/3, 131_002), plus 074_001/2/4
  whose solutions are 4 defmacros + 1 def while the target enumerator is
  defmacro-blind. `missing(:fim)` now delegates to `Fim.missing_units/2`
  (pool-capped, same honesty rule as the tfim fix; 258 tests green).
- **12 fim units sit on the 4 bundle-parent seeds** (016_001, 018_001, 019_001,
  102_001) — kept visible as pending; decision below.
- **7 fim units are winnable** (100_001, 100_003, 623_002, 625_003 ×2,
  625_004, 626_004) + ~3 winnable variations (098_001 ×2, 100_001).
  034_001's 3 variations fail distinctness systematically (model converges on
  the same `reconcile/3` API) and 018_001's variation fails 0/N tests every
  attempt — both parked with the triage decisions.

**A focused relaunch is running** for the winnable units only, using the new
`GEN_EXCLUDE_SEEDS=016_001,018_001,019_001,034_001,102_001` filter (added +
tested), so the loop cannot repeat yesterday's rejected-nearly-everything run.

### Queued decisions for Kamil (updated 2026-07-12)

1. **fim on bundle parents — RESOLVED 2026-07-12: FIXED** (Kamil's criterion:
   fix if the units would be valuable — they are: multi-file Phoenix/Ecto FIM
   is scarce, realistic data, and Phase 3 bundles would hit the same wall).
   The gap was two-sided and both sides are landed + deterministically
   verified with zero LLM calls:
   - *Eval:* bundle children were reconstructed into a marker-stripped blob
     and plain-compiled — no kit, no Repo boot — so tier-B/repo parents failed
     0/N even on perfect skeletons. `Fim.reconstruct_bundle/3` now maps the
     skeleton back onto the parent's `<file>` files and grades through the
     same tier machinery as the parent. Pre-flight on all 4 seeds with gold
     candidates: 14/14, 31/31, 20/20, 18/18, 0 warnings; a raise-mutant of an
     exercised target fails 14/14 (gate discriminates), an unexercised target
     survives (correctly rejected as a fim target).
   - *Gen:* `deterministic_skeleton` now builds bundle skeletons from the
     marker-stripped parent and REPLACES-or-INSERTS the fence (a missing fence
     was the dominant `:contract` rejection). Hallucination filter and pool
     caps use the same view.
   The 4 bundle seeds (12 units) rejoin the runnable backfill; a focused run
   launches when the current 7-seed run finishes.
2. **defmacro-blind target enumeration — RESOLVED 2026-07-12: FIXED** (same
   criterion: macro FIM — quote/unquote bodies, `__using__`, assertion
   helpers — is scarce, distinctive metaprogramming data). Audit found the
   pipeline was ALREADY macro-ready end to end: `build_skeleton`/`splice`
   handle defmacro, `Fim.mutate` guts them, and a gutted macro blowing up
   harness compilation is an errored-kill (`errored_against_mutant?`, wired
   2026-07-10). Only the enumerators were blind: `Mutation.all_functions/1`
   (selector pool + isolation gate — safe there, inconclusive grades just keep
   scanning) and the gen-side covered-targets parser now count
   defmacro/defmacrop. Nine 074_x macro targets perma-rejected on 07-04/07-07
   — BEFORE the errored-kill fix existed, i.e. under tooling that could not
   see a macro kill — were purged from `logs/fim_rejected.jsonl` (the one
   non-074 entry stays). Pre-flight with zero LLM calls: gold
   `assert_recent/2` grades 17/17 + 0 warnings, its mutant errored-kills.
   The 6 units on 074_001/2/4 rejoin the runnable backfill.
3. **variation distinctness for 034_001 — RESOLVED 2026-07-12: FIXED** (same
   criterion; the fix is generic, not 034-specific — 098_003 and 101_002 hit
   the same rejection, and Phase 3 has 490 bases × 3 variation slots ahead).
   Root cause was an information gap, not bad data: the distinctness gate
   (already pre-cycle, zero grading cost) rejects a candidate whose public
   function set equals the base's or an accepted sibling's — but the
   generation prompt only listed existing variation NAMES, never the taken
   API sets, so the model kept converging on the base's natural surface
   (`reconcile/3`) under different task names. `Prompts.variations` now
   states the gate's exact criterion as a HARD CONSTRAINT with every taken
   set listed; `Variations.run` threads the sets it already computed for the
   gate into the prompt. No perma-skip ledger for these: distinctness
   failures are stochastic (LLM-quality), and a permanent verdict is only
   sound for deterministic gates — repeat offenders after this fix go to a
   human triage list instead. NOTE: rejected variation candidates were never
   in the dataset (staging-only; promotion happens on accept), so no
   accepted data was ever deleted by these rejections. 018_001's variation
   (0/N tests every attempt) is a different failure mode — watch it on the
   next pass.
4. **tfim describe-carving — RESOLVED 2026-07-12: FIXED** (same criterion;
   the strongest case of the four: tfim is fully deterministic — gold carved
   from the harness, prompt templated, gates local — so the unlock costs ZERO
   tokens). The carver, isolation gate, embeds resync and bookkeeping are now
   describe-aware with ExUnit-style qualified names; the eval splice needed no
   changes (already indent-generic). Backward compatibility proven corpus-wide:
   resync dry-run over all 2,924 existing tfim embeds reports unchanged.
   Pre-flight: seed 037_003 (zero top-level tests — minted nothing before)
   carved 8 nested tests, all isolation-kill gated, all grade 8/8 clean.
   **Registry: test_fim 0 → 219 pending units / 27 seeds — all free to mint;
   the running backfill loop mints them as derived work.**

### All four queued decisions are now resolved (2026-07-12, Kamil's criterion:
### fix if valuable). Bundle-fim additionally needed two live fixes after its
### first real run (see git log): the staged parent lacked manifest.exs (tier
### misdetection — the docs/10 §5.13 class, now fixed at read_triplet), and
### repair replies could clobber the deterministic skeleton (now re-derived
### after every repair).

Still waiting on Kamil (unchanged): nightly-sweep systemd timer install
(§4.1.10) and the §4.2 / §5.2 decisions.

### History of this round (compressed — details live in the git log and docs/12)

- **2026-07-10:** Phase 2 top-up launched (111 seeds / 710 units). Stale
  child-prompt resync, seed self-check fix, format gate re-greened.
- **2026-07-11:** embed-staleness checker built + all 64 families classified
  (ledger `logs/embed_classify/recovered.jsonl`); remediation tool
  `scripts/resync_embeds.exs` built and self-tested (one-shot, delete at the
  line; ledger `logs/embed_resync.jsonl`).
- **2026-07-12 overnight:** first pass finished; 84 accepted dirs committed;
  171 embeds resynced, 12 redesigned-parent golds hand-fixed;
  `EvalTask.Fim.signature_stub` continuation-`do:` bug fixed; embed CI gate
  wired. Second pass exposed the phantom-326: `missing(:test_fim)` counted
  units the carver can never mint (describe-grouped harnesses); now delegates
  to `TestFim.mintable_candidates/2` — test_fim honestly reads 0 pending.
- **Loop runbook** (still current): detached loop = PID in
  `logs/backfill_phase2.pid`, log `logs/backfill_phase2.log`. Never restart
  while a `beam.smp` is alive; if dead, the relaunch command is idempotent:
  `GEN_ONLY=backfill scripts/run_detached.sh logs/backfill_phase2.log mix run scripts/generate.exs`
  (add the current `GEN_EXCLUDE_SEEDS` list from "Where we are right now").

---

## The two modes (definitions)

**STEADY STATE** — one command produces new data
(`scripts/run_detached.sh logs/loop.log mix run scripts/generate.exs`), every
quality check lives inside that loop or in CI, and nothing needs to be "caught
up". No backfill tooling exists in the repository.

**CATCHING UP (improvement round #N)** — we raised the quality standard, so
existing data must be brought up to it. Every round follows the protocol in
docs/12 §7.3: bump the standard → wire the new check into the loop + CI *first*
→ write a one-shot upgrade tool with its own ledger → run it to completion →
verify the whole corpus → **delete the tool** → flip this file back.

## Round history

| # | Round | Dates | What was raised | Status |
|---|-------|-------|-----------------|--------|
| 1 | 2026-07 QA catch-up | 2026-07-07 → … | prompt↔test consistency, mutation & format gates, embed staleness, blind screening (docs/10) | **in progress** |
