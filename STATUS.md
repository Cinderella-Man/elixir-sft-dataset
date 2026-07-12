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
- [ ] Phase 2: derivative top-up run **LAUNCHED 2026-07-10 ~18:45** (detached,
      `logs/backfill_phase2.log`; 111 seeds / 710 units). Three passes done by
      2026-07-12 (details in "Where we are right now"). After the two
      registry-honesty fixes (phantom-326 tfim, pool-capped fim) the honest
      remainder is: **10 winnable units running now** (7 fim + 3 variation,
      relaunched 2026-07-12 with GEN_EXCLUDE_SEEDS), **12 bundle-fim units +
      4 variation units parked behind the queued triage decisions**. Phase 2
      closes when the winnable run finishes AND Kamil rules on decisions 1–3
      (each either deletes its parked units from the registry or schedules the
      fix that makes them producible)
- [ ] Phase 3: new generation resumed and first batch validated
- [ ] The line: catch-up tooling deleted per docs/12 §7.2, this file flipped

### Where we are right now (2026-07-12 ~13:00 — push unblocked, Phase 2 tail triaged, focused relaunch)

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
4. **tfim describe-carving** (unchanged from yesterday): §5.3.1 recommends
   describe grouping, the carver only takes top-level tests — decide before
   Phase 3.

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
