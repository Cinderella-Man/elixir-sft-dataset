# PROJECT STATUS

**GOAL (Kamil 2026-07-19): the existing families as extended and as high
quality as possible — the dataset must be GOLD. When everything below is
done and verified, this file becomes one line: "catch up finished, ready
to generate new tasks." Nothing else belongs here.**

Rules: CONTEXT.md HOW-WE-WORK (two-tier findings, pilots, ledgers,
detached+monitored jobs, one solved item = one commit).

---

## IN FLIGHT (2026-07-20 evening — G2 re-measure COMPLETED; G1 sweep
## crashed at root 269/330 and was fixed + relaunched, see below)

- **G1 sweep — semantic_review over all roots (3rd launch).** pid: see
  `logs/semantic_review_full.pid` (last line), log
  `logs/semantic_review_full.log`, ledger `logs/semantic_review.jsonl`.
  Crash 2026-07-20 ~17:50 at 101_003 (root 269/330 of run 2): a verify
  reply with malformed JSON (stray `;`) made BOTH script validators
  return the raw `%Jason.DecodeError{}` struct as the contract-violation
  message, which `Cycle.generate`'s log interpolation can't stringify.
  Fixed 2026-07-20 in scripts/semantic_review.exs ONLY (both validators
  now `Exception.message/1` the struct → the reminder-retry path works
  as designed; no lib/ edit, review_sha untouched so all 333 ledger rows
  stay valid). Also dropped the 100_002 row (its one finding was never
  verified — error_max_turns 5/5 exhausted; relaunch redoes it fully;
  backup in session scratchpad). ~60 roots remain; rides credit windows.
  Interim signal: **203 of 333 reviewed roots carry ≥1 confirmed
  finding.** Idempotent relaunch: `scripts/run_detached.sh
  logs/semantic_review_full.log mix run scripts/semantic_review.exs --
  --go --sample 400`

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

**G1. Latent semantic defects — full review of EVERY root (not a
sample).** Rubric pass #2 measured 1 real gold defect per 42
execution-perfect roots; extrapolated ~6-8 more hide in the ~330 roots.
Run `semantic_review` over ALL roots + `rubric_judge` full two-family
pass; triage every finding against the artifacts; `close_gaps` the
confirmed ones; every fix cascades + gets its generator gate (rule 7).

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
- **Task B:** port the detector into the S9 block of
  lib/gen_task/evaluator.ex as a HARD check + evaluator unit tests.
  **WINDOW NOW OPEN (2026-07-20): the G2 mutants sweep completed**, so
  flipping gate_sha([Mutation, Evaluator]) no longer invalidates an
  in-flight measure (the finished report is preserved in the log; the
  post-strengthen re-measure re-runs under the new gate anyway, which is
  correct per rule 7). Safe during the review sweep: semantic_review
  never loads Evaluator/Prompts and its ledger is template-keyed. Lint
  half is DONE (two tiers, frozen-evidence exclusion, error-atom guard,
  dedoc_ shielded from --fix-prompts).

**G1b. Review-sweep interim signal (2026-07-20, 54/330 roots in): 30
roots carry CONFIRMED findings — far above the 1-per-42 estimate; expect
a close_gaps campaign of 100+ families.** Emerging classes beyond
dormant-timer: (i) `:name` registration promised, never tested (spot-
verified by hand on 005_003 + 007_001 — TRUE; too pattern-varied for a
text lint, names pass through variables); (ii) fake-clock self-advancing
assertions that hold vacuously (013_001/013_004 high); (iii)
gold_defects incl. dead branches and @type-vs-prompt contradictions
(hand-work per close_gaps contract, never auto-strengthened).
- **Task B for (i)+(ii) — lib-edit window NOW OPEN** (same window as
  G1a's S9 port; the mutants sweep completed 2026-07-20):
  harden the promise-coverage audit checklist in lib/gen_task/prompts.ex
  with the three recurring misses (registration :name, default clock,
  automatic timer observation) + a vacuity item (an assertion that the
  test's own clock advances make true proves nothing).
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
