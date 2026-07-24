# PROJECT STATUS

**GOAL (Kamil 2026-07-19): the existing families as extended and as high
quality as possible — the dataset must be GOLD. When everything below is
done and verified, this file becomes one line: "catch up finished, ready
to generate new tasks." Nothing else belongs here.**

Rules: CONTEXT.md HOW-WE-WORK. Done work lives in docs/15 + git history.
Finding details for the current campaign: `logs/semantic_review.jsonl`
(machine) + `docs/19-gold-defect-triage.md` (hand work).

---

## NEXT ACTIVITIES (in order)

1. **[DONE 2026-07-22] MERGED HAND QUEUE (activities 3+4) — CLOSED.**
   All 11 rubric triage roots fixed; every docs/19 finding DONE or
   refuted with artifact evidence; 032_002 re-judged clean on its
   fixed sha (4/4/4, 4/5/5 — the errored row superseded). Full record
   in docs/15 + the commit chain. Standing lessons now in force:
   per-finding evidence checks on any sweep refutation; bugfix
   children + repair_/dialog_ copies checked on EVERY gold edit (the
   pre-push perfect sweep is the backstop); stage with git add of the
   tasks tree, never bare multi-globs.

3. **[DONE 2026-07-22] Weak-assertion tail (G2) — CLOSED, floor
   PROMOTED.** Machine phase 7/9; hand-tails 064_001 (0.82) + 071_001
   (0.67); nine repair_-dir pairs refreshed and verified both sides;
   corpus re-measure: 0 families < 0.5, sub-0.6 tail = the two 037
   anonymizer families, PROVEN at ceiling (survivors live in the
   {:fake, seed} derivation arithmetic the prompt deliberately leaves
   unspecified — S6-unpinnable). validate.exs --semantic-mutants now
   FAILS below 0.6 for non-waived non-wt families (waivers are
   recorded verdicts with evidence; bite-proven both ways) and runs
   in weekly CI off the committed ledger. The strengthen-archiving
   Task-B rider is closed-as-moot: the tool retires at the line and
   the floor gate is the standing protection.

4. **[DONE 2026-07-22] Harness style debt (G4) — CLOSED.**
   The :sys.get_state/replace_state purge ALREADY RAN 2026-07-14 (34
   applied rows in logs/rewrite_reachins.jsonl; zero reach-ins on
   disk — the old "52" counted the 102-family's DOMAIN-API get_state/2
   and derivative copies; :sys.suspend/resume uses are deliberate
   stall-testing, not reach-ins). Remaining:
   (a) DONE 2026-07-22: sleep audit CLOSED — the 38 suspicious files
   collapse to 18 unique parents (rest are wt_/repair_/dialog_
   mirrors) and EVERY sleep is a sanctioned class (bounded poll
   helpers, payload sleeps, 013-family tick-catch-up, 015-family
   real-timer waits, 023-family clock-set-then-real-sweep hybrids);
   none masks a missing clock advance. Verdict row appended to
   logs/sleep_audit_worklist2.jsonl with per-family classes;
   (b) DONE 2026-07-22: the tfim_107_002 hard fail was child _11's
   STALE GOLD still asserting the pre-widening 1ms upper tolerance
   (elapsed < 1_001_000 on a real 1s timer — a 5us overshoot under
   parallel load failed it); the parent test had already been widened
   to 1_500_000 with the jitter rationale. Gold re-carved from the
   current body (raw slice, <=98 cols), 1.0 x4;
   (c) DONE 2026-07-22: S9 evaluator timer-detection spec-scoping
   landed (content-keyed contract_text; 3 unit tests; 415 green).
   The post-flip full re-measure LANDED 2026-07-23: 663 tasks,
   corpus kill 83.7% (mean per-task 0.853), floor gate EXIT 0 with
   only the two waived 037 families below 0.6 — ledger sha-current
   for the weekly CI gate.

6. **[ ] @doc prose truth on existing golds (G5) — FIX LANE (9/74 done).**
   Sweep @doc claims vs the harness-validated code / prompt contract; fix
   contradictions/phantom_api by aligning the doc, unpromised by softening or
   adding a prompt sentence + test. (Manual finding-classes PILOT of 5 golds
   closed 2026-07-23 → docs/15.)
   FULL SWEEP: TOOL PILOT VALIDATED 2026-07-24 (--limit 5: 3 clean, 2
   real grounded findings — 001_002 moduledoc "O(1) state per key" is
   unpromised+false [stale {key,window} entries accumulate unbounded when
   cleanup :infinity]; 002_001 @doc ":half_open_max_probes = concurrent"
   is a contradiction [probe_count only increments, never decremented on
   completion + handle_call serializes → it bounds CUMULATIVE probes],
   spot-verified against code lines 29/138/141/175/179). Census: 335 roots.
   FULL SWEEP DONE 2026-07-24 01:48 (335 roots, logs/doc_truth.jsonl):
   273 clean, 62 roots with findings, **74 findings total** = 42 contradiction
   + 31 unpromised + 1 phantom_api. Report-only (changed nothing).
   FIX LANE (IN PROGRESS) — each finding is a single-pass judge HYPOTHESIS
   (no adversarial verify in this tool), so VERIFY per-artifact before any
   edit (rule 10 / the 101_003 near-miss). Read the ledger for all 74:
     python3 -c "import json;[print(r['task'],f['class'],f['why'][:80]) for l in
       open('logs/doc_truth.jsonl') for r in [json.loads(l)] for f in r.get('findings',[])]"
   Fix types: contradiction → align the @doc/@moduledoc to the harness-validated
   CODE (doc drifted); unpromised → soften/cut the claim OR add a prompt sentence
   + anchored test; phantom_api (103_001 purge/4→purge/3) → fix the doc arity;
   over-reads → skip. Doc edits don't change behavior (perfect score unaffected)
   but DO change solution.ex → cascade the embed resync battery (--apply) per
   batch + re-verify (check_embeds 0, perfect on touched, S6 fresh if any prompt
   touched). Batch-commit. Two-tier (rule 7): a generator-preventable class gets
   an accept-time doc-truth gate.
   CASCADE COST IS HIGH (learned batch 1): a solution.ex doc edit cascades to ~18
   derivatives; editing a FUNCTION's @doc (not just moduledoc) also stales that
   function's fim-child gold (re-carve: apply the same @doc edit to the child) AND
   the family's bugfix golds (delete + re-mint via GEN_ONLY=topup skip-all-except-
   bugfix, scoped only_idea — stale_gold is never --apply-healable). ~1 batch of
   ~10 findings per session is the sustainable pace.
   BATCH 1 LANDED + PUSHED 2026-07-24 (54360d577 + tail → 6aab481e4): **9/74**
   fixed across 7 families (103_001 phantom_api; 044_001 ×3; 002_001; 002_003;
   015_003; 015_004; 005_003). **65 remain** in logs/doc_truth.jsonl (contradiction
   + unpromised; 0 phantom_api left). The push had a long cascade TAIL worth
   heeding next batch: (1) my one-line @doc additions ran >98 cols → house-style
   fail → wrap multi-line, and CHECK max line length on the edited solution.ex
   BEFORE cascading (multiple `--only` flags do NOT OR — only one applies; use the
   pre-push or per-dir validate); (2) editing an idea's family drags its SIBLINGS
   into the pre-push's parallel validate, which surfaced a pre-existing 002_002
   flake (fixed, see below); (3) a harness edit needs a blind RE-SCREEN (S6 sha)
   + adapt/dedoc/tdd cascade, not just wt/tfim. NEXT batch: ~10 more — start with
   the [high] contradictions 013_002/072_001/073_001/074_001 (may be CODE gaps not
   doc drift — verify prompt+harness carefully).

   6b. **[DONE 2026-07-24] 002_002 rolling-window CB flake FIXED (found during
   G5 batch 1).** The setup started the named `:test_cb` GenServer with a BARE
   `start_link` — the registered name frees only asynchronously on the linked
   test's exit, so under parallel-eval load the next test's setup raced a lingering
   `:test_cb` → `{:error, {:already_started, _}}`, 1/23 (known flake since
   2026-07-13). Fix: `start_supervised!` (deterministic teardown; name stays
   `:test_cb`). Cascaded (wt/tfim/adapt/dedoc/tdd + blind re-screen GREEN), pushed
   in 6aab481e4. Task B candidate (not yet built): a lint flagging
   `start_link(name: <fixed atom>)` in a harness `setup` without `start_supervised`
   — same family as the temp-path lint. Recorded for the finish-line gate sweep.

7. **[DONE 2026-07-23] Family spot-checks (G6, CONTEXT rule 8) —
   CLOSED.** Deterministic sha-ordered stratified sample (seed string
   "g6-2026-07-23", reproducible): 10 accepted units across all 10
   strata (manual-era base, generated-era base, wt, tfim, bugfix,
   repair, adapt, dedoc, tdd, specfim) — ALL PASS on detailed reads;
   3 rejected verdicts probed SOUND (2 bugfix mutant-survivor rejects
   verified against harness reality, 1 sfim vacuous-target reject);
   1 whole-family read (044_002, 32 dirs) coherent. Zero new
   defects. Ledger: logs/g6_spotchecks.jsonl (14 rows). Standing
   practice (rule 8) continues at every future accept/reject tool.

8. **[DONE 2026-07-23] Screen depth (G9) — CLOSED.** All 27 standing
   hard-keeps 3-solved (probe 10 + full 17, ledgered): **16 flip to
   blind_solvable** by last-3 majority (7 at G-G-G) and **11 stay
   keep_class** (8 at R-R-R — 020_002/3/4, 025_002, 040_001, 041_004,
   045_003, 064_001; 3 at single-green splits correctly kept hard).
   Task B landed earlier the same day: export difficulty tier =
   majority of last 3 verdicts (unit-tested), so the metadata updates
   itself at the next export refresh from these very rows. Full
   record → docs/15.

9. **[ ] Extension loop (G8) — PROBE PASSED; full run is the LAST activity.**
   Probe CLOSED 2026-07-23 (full record → docs/15): lever landed (4e1fe704a,
   GEN_VARIATION_SLOTS tunable); 3 new b=5 variations minted + confirmed GOLD
   across diverse families — 065_005 (saga), 091_005 (FSM/GenServer), 034_005
   (parallel reconciler) — each clean on 12 accept gates + hand review +
   semantic_review (0 confirmed) + rubric (5/5/5 ×2). The probe FOUND + FIXED a
   real generator bug (dialyzer repair_report crash, Task B 67499d55b) that would
   have lost every GenServer mint — exactly the §0 payoff.
   REMAINING (run LAST, after items 5 + 6 land so new mints carry every gate +
   varied register): the FULL extension loop — GEN_VARIATION_SLOTS=4 over ALL
   converged ideas, detached, to give each a distinct 5th variation + its
   derivatives. Probe yield ≈ 5 repair-attempts/accept; some families saturate at
   4 (091's 1st mint was a weak-harness reject) — budget retries, don't force.
   NOTE: the 3 probe roots were minted variations-only, so they still LACK
   derivatives (fim/wt/tfim/bugfix/adapt/dedoc/sfim/tdd/specfim/bundlefim); the
   extension loop (or a plain GEN_ONLY=topup run) mints them — they are valid
   standalone _01 tasks until then (no gate breaks on missing children).

   4c. **[DONE 2026-07-24] Pending repair-mint — RESOLVED (not mintable).**
   mint_repairs ran for real (unheld) during the G5 bugfix re-mint: of 230
   mintable (rejected→accepted) candidates, 89 already exist and the 141
   candidate-new all came back `unverified` — they FAIL the real verification
   (a "rejected" attempt that actually grades green, or a fix that doesn't grade
   green in isolation, teaches nothing), so ZERO new repair dirs were promoted
   (repair_ count steady at 90). The 141 are correctly skipped, not owed work.
   Closed; no Task B (mint_repairs already self-verifies).

   4d. **[ ] Minor existing-data note (found 2026-07-23):** 6 corpus golds spec
   start_link with the narrow {:ok,pid}|{:error,term} form (vs ~395 using
   GenServer.on_start()). Benign overspec; would flag under a full-corpus dialyzer
   pass. Low priority — fold into any future corpus dialyzer audit, not urgent.

10. **[ ] Finish line.** Full sweeps (perfect + fim + mutants +
    decontam), export refresh, README — then this file becomes the
    one-liner. (The docs/18 training-run handoff stays available to
    Kamil at any time; gold-first proceeds regardless.)
