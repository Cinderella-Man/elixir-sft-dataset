# PROJECT STATUS

**GOAL (Kamil 2026-07-19): the existing families as extended and as high
quality as possible — the dataset must be GOLD. When everything below is
done and verified, this file becomes one line: "catch up finished, ready
to generate new tasks." Nothing else belongs here.**

Rules: CONTEXT.md HOW-WE-WORK (two-tier findings, pilots, ledgers,
detached+monitored jobs, one solved item = one commit).

---

## IN FLIGHT (2026-07-20 — the 07-19 sweeps died by SIGTERM at 14:34, machine
## rebooted 10:56; both ledgers survived and both scripts resume by sha)

- **G1 sweep relaunch — semantic_review over all roots.** pid: see
  `logs/semantic_review_full.pid` (last line), log
  `logs/semantic_review_full.log`, ledger `logs/semantic_review.jsonl`.
  1/331 roots done (001_001: 1 confirmed harness_gap finding — needs G1
  triage). Expected: ~330 rows appended, each ≤1 review + 2 verify LLM
  calls; rides credit windows (15 min/attempt, forever). Idempotent
  relaunch: `scripts/run_detached.sh logs/semantic_review_full.log mix run
  scripts/semantic_review.exs -- --go --sample 400`
- **G2 re-measure relaunch — validate --semantic-mutants, QUEUED behind
  the nightly sweep** (nightly pid 3279 started 11:14; running both
  grading sweeps at once turns CPU contention into false rows — the
  nightly's own guard exists for exactly this). validate.exs now resumes
  from the ledger (rule-2 patch, piloted on 001_001: skip path exact).
  494/~600 tasks already ledgered at current shas. When nightly exits:
  pilot the measure path on one unmeasured task, review, then
  `scripts/run_detached.sh logs/semantic_mutants_full.log elixir
  scripts/validate.exs --semantic-mutants`
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
  **QUEUED until the G2 mutants sweep completes** — editing Evaluator
  flips gate_sha([Mutation, Evaluator]) and invalidates every
  semantic-mutants ledger row mid-measure. Lint half is DONE (two tiers,
  frozen-evidence exclusion, error-atom guard, dedoc_ shielded from
  --fix-prompts).

**G2. Weak-assertion tail — strengthen to the 0.6 kill floor
corpus-wide, then make the floor a corpus GATE.** Corpus semantic-mutant
kill ~71%; the 0.6 floor holds at accept for new tasks only. Re-measure
per family (`validate --semantic-mutants`), `strengthen_harnesses` the
tail, re-measure, then promote the floor from report-only to a failing
check in validate/CI.

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
