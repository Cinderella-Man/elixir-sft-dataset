# PROJECT STATUS

**GOAL (Kamil 2026-07-19): the existing families as extended and as high
quality as possible — the dataset must be GOLD. When everything below is
done and verified, this file becomes one line: "catch up finished, ready
to generate new tasks." Nothing else belongs here.**

Rules: CONTEXT.md HOW-WE-WORK (two-tier findings, pilots, ledgers,
detached+monitored jobs, one solved item = one commit).

---

## IN FLIGHT (2026-07-20 night — both sweeps COMPLETE, both lib-edit
## Task-B gates LANDED (docs/15); gate_sha is now STABLE for the whole
## campaign — no lib/gen_task edits until it ends, rule 7 corollary.)

- **close_gaps PILOT (rule 9) — one family, 001_001_rate_limiter_01.**
  The campaign dry list is 183 families (~2 LLM calls each). Pilot log
  `logs/close_gaps_pilot.log`, pid in `logs/close_gaps_pilot.pid`,
  ledger `logs/close_gaps.jsonl` (gate-sha-stamped; all pre-2026-07-20
  rows are invalid under the new Evaluator sha — intended). 001_001 is
  the dormant-timer exemplar, so the pilot exercises BOTH new gates
  end-to-end: the hardened promise_audit must produce a real-interval
  observation test and the result must clear the new S9 dormant check.
  Review the pilot IN DETAIL (candidate in logs/gap_candidates/, ledger
  row, applied diff + wt_/tfim resync) before the full launch.
  Idempotent relaunch: `scripts/run_detached.sh
  logs/close_gaps_pilot.log mix run scripts/close_gaps.exs -- --go
  --only "001_001*"`. Full campaign after pilot review: scoped batches
  (NOT unscoped --go — 6 hand-closed families are phantom todos, see
  tool header), HIGH families first (`--high-only` batch, then rest).

## NEW from the 2026-07-20 nightly (6 fails, triaged)

- **tfim_107_002_keyed_event_aggregator_..._11: hard stability-3 fail
  (1/17), but 7/7 GREEN solo afterwards** — zero prior flake history.
  Load-dependent timing failure (batching windows). Remaining task (a):
  reproduce under controlled parallel load, capture the failing test,
  fix or document the timing contract (G4 family). (Task (b) — hard-fail
  ledger rows with serial failure detail — LANDED 2026-07-20 and
  self-tested with a planted failing task; the next occurrence is
  diagnosable from flaky.jsonl alone.)
- **G7 instrumentation piloted-pending:** `scripts/mint_repairs.exs` now
  ledgers WHY each unverified pair fails (`logs/repair_unverified.jsonl`)
  — uncommitted until a rule-9 pilot run; run it AFTER the nightly (it
  grades locally).

## THE GAP LIST (ranked; strike items only when fixed + gated + verified)

**G1. Latent semantic defects — SWEEP COMPLETE 2026-07-20 (395 roots, 0
errors): 327 confirmed findings across 236 roots (60%!). Split:
harness_gap 264 / gold_defect 55 / prompt_defect 8; severity 48 high +
279 medium; per-root: 159 clean, 159×1, 64×2, 12×3, 1×4.** The
extrapolated "~6-8 defects" estimate was off by ~40×. Remaining, in
order: (1) lib-edit window Task-Bs — DONE 2026-07-20 (docs/15); (2)
triage worklists — harness_gaps are mechanized by close_gaps directly
from the ledger (183-family dry list), and the 63 gold/prompt-defect
hand-work findings (11 high, 52 families) are now enumerated in
**docs/19-gold-defect-triage.md** — work top-down, one family = one
commit + cascade; (3) the close_gaps campaign (pilot IN FLIGHT above)
+ cascades + resync_adapt/dedoc --apply; (4) `rubric_judge` full
two-family pass still owed after that.

**G1a. Dormant-timer class (2026-07-20, generalized from 001_001's
confirmed review finding).** Prompt promises an automatic periodic timer
(`Process.send_after` + interval option); no test ever enables it — a
no-op scheduler passes. Deterministic enumeration: `mix run
scripts/lint_harnesses.exs` → 83 CONFIRMED dirs (21 roots; every one
takes the documented `:infinity` escape in all tests) + 8 DORMANT?
needs-read dirs.
- **Task A:** close_gaps the 21 confirmed roots (add-only automatic-sweep
  observation test, e.g. two-round reclamation via a wider-window probe).
  Cascade VERIFIED 2026-07-20: close_gaps does wt_+tfim; adapt_/dedoc_
  harnesses are byte-for-byte projections with standing CI drift gates —
  after applying, run `resync_adapt_embeds -- --apply` and
  `resync_dedoc_embeds -- --apply` and the 62 derivative DORMANT entries
  collapse into the root fixes. Then hand-read the 8 DORMANT? dirs
  (015-family + adapt_107_004 observe timers positionally/via
  assert_receive — likely fine; adapt_023_004 + adapt_006_002 never
  configure the promised sweep — likely real; note the adapt_ prompt
  embeds the BASE gold, so its timer promise can be an artifact of the
  projection rather than the variation's contract).
- **Task B: DONE 2026-07-20** (S9 hard gate landed, docs/15) — only
  Task A (the 21-root close_gaps batch + cascade + the 8 DORMANT?
  hand-reads) remains for G1a.

**G1b. Review-sweep interim signal (2026-07-20, 54/330 roots in): 30
roots carry CONFIRMED findings — far above the 1-per-42 estimate; expect
a close_gaps campaign of 100+ families.** Emerging classes beyond
dormant-timer: (i) `:name` registration promised, never tested (spot-
verified by hand on 005_003 + 007_001 — TRUE; too pattern-varied for a
text lint, names pass through variables); (ii) fake-clock self-advancing
assertions that hold vacuously (013_001/013_004 high); (iii)
gold_defects incl. dead branches and @type-vs-prompt contradictions
(hand-work per close_gaps contract, never auto-strengthened).
- **Task B for (i)+(ii): DONE 2026-07-20** (promise_audit checklist
  hardened with the three miss classes + NON-VACUOUS rule, docs/15).
- **Task A:** flows through the standing plan — close_gaps batch after
  the review sweep completes (resumes by sha; gold_defect families are
  hand-work).

**G2. Weak-assertion tail — strengthen to the 0.6 kill floor
corpus-wide, then make the floor a corpus GATE.** Re-measure COMPLETE
2026-07-20 (`SEMANTIC-MUTANT REPORT COMPLETE` in
`logs/semantic_mutants_full.log`; ledger `logs/semantic_mutants.jsonl`,
2,475 rows — the report regenerates from the ledger, and the tail list
lives in the log even after Evaluator edits flip gate_sha). Remaining:
`strengthen_harnesses` the tail (QUEUED behind the review sweep +
close_gaps so harness edits don't race the reviewer), re-measure, then
promote the floor from report-only to a failing check in validate/CI.

**G3. Prompt-register monotony.** ~76% of seed prompts open "Write
me…"; every templated shape (tfim/wt/sfim/specfim/tdd/bundlefim) has ONE
frozen register. (a) Templated shapes: deterministic template ROTATION
(3-5 variants each, resync gates re-derive — cheap, no LLM); (b) seed
prompts: LLM register rewrite with mandatory blind re-screen per rewrite
(screen_blind_solve restored). Generator side: rotation wired into the
templates so future mints vary too.

**G4. Harness style debt.** 52 April-era harnesses pin internals via
`:sys.get_state` (`rewrite_reachins`, restored path exists); 142 use
`Process.sleep` — audit each: legitimate (documented timing contract) or
debt (needs injected clock); fix the debt class.

**G5. @doc prose truth on EXISTING tasks.** The DOC TRUTH rule guards
new authoring only. Sweep every gold's @doc behavioral claims against
the prompt contract (the F12 class); un-promised claims either get
prompt sentences + anchored tests (promise-audit machinery) or get cut.

**G6. Family spot-checks (CONTEXT rule 8, both sides).** Structured
detailed READS — not scripts — of sampled families across eras and
shapes: prompt vs gold vs harness coherence, plus reject-ledger spot
checks. Findings feed G1's triage; sampling plan and read notes ledgered.

**G7. Extension: 134 unverified repair-chain pairs.** The last topup
printed `mintable (rejected → accepted) pairs: 223 | minted: {exists:
89, unverified: 134}` — investigate why 134 fail verification; recover
what's honestly recoverable into repair/dialogue data.

**G8. Extension headroom (Kamil to confirm scope):** more variations per
base idea (b=005+) would extend existing families without new ideas —
LLM cost per variation ≈ one base cycle. Flag: is this in-scope
"extension" or already "new tasks"?

**G9. Screen depth for hard families.** S6 = one green blind solve;
keep-class roots carry documented reds. Consider 3-solve consistency on
the ~50 keep/hard roots to sharpen the difficulty metadata the export
carries.

---

**After the list:** full sweeps (perfect+fim+mutants+decontam), export
refresh, README, then the one-liner.

**Waiting on Kamil:** G8 scope; the docs/18 training run (any time — its
measurements can reprioritize G2/G3 spend but Kamil chose gold-first).
