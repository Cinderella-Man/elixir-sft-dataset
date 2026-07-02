# 05 — Generation-Loop Audit & Corpus Test Results

Date: 2026-07-02. Method: full-corpus test runs (`validate.exs`, `run_all.exs`) + a multi-agent
code review of `lib/gen_task/**` across 5 dimensions, each finding adversarially verified. This
answers two questions: **how do we test every generated task**, and **are we doing everything we
can** in the loop.

---

## 1. How to run tests for ALL generated tasks

Two scripts cover the whole corpus (single-file + multi-file + FIM), one BEAM per task:

```bash
# STRICT PASS/FAIL GATE — every reference must be green, every FIM target mutation-killed.
# Exit 0 iff all pass. This is the one to run after any generation batch.
elixir scripts/validate.exs
elixir scripts/validate.exs --fim-only     # just the FIM mutation check
elixir scripts/validate.exs --green-only   # just reference-green

# SCORED RUN — same coverage, plus the analysis/compilation/overall score per task.
elixir scripts/run_all.exs --parallel 6
#   → results/<task>.json, results/report_<ts>.json, results/summary_<ts>.txt
```

`validate.exs` discovers tasks via `EvalTask.Discovery.all()` (not a glob), so it automatically
covers new tasks. Use it as the acceptance check; use `run_all.exs` when you want the score
distribution (to catch quality drift the pass/fail gate misses).

### Results of the full run (343 tasks)

| Metric | Value |
|---|---|
| Reference-green | **342/343 pass** (1 skip = Postgres task) |
| FIM mutation | **169/169 pass** — every FIM target is genuinely exercised |
| Compiled | 342/343 (99.7%) |
| Avg overall score | **0.983 / 1.0** |
| Loop-generated avg | **0.981** (tests 1.0, analysis 0.946, **compilation 0.925**) |
| Hand-authored avg | 0.985 (tests 0.999, analysis 0.941, **compilation 0.991**) |

**The one reference-green failure is `032_002_csv_to_ecto_batch_ingestion…` (1/8 tests) — a
hand-authored Ecto task, NOT loop-generated.** It predates the loop; worth fixing separately.

**Verdict on generated quality:** loop tasks are on par with the hand-authored gold set overall,
with **perfect test scores**. The *entire* quality gap is **compile warnings**: 35/167 generated
tasks carry warnings (some FIM reconstructions 10–18, flooring compilation to 0.0), because the
accept gate never looks at warnings. That is the single biggest lever below.

---

## 2. Are we doing everything we can? — 21 verified findings

The loop is fundamentally sound: the green + raise-mutant accept gate holds, tasks are add-only,
resume is durable, and output quality matches gold on tests and docs. But there are concrete,
verified improvements, grouped by theme and priority.

### P1 — a robustness bug that can hang an overnight run
- **[HIGH] Usage-limit misclassification → infinite 15-min-sleep loop** (`opus.ex:132`, `:22`).
  `classify/2` checks `usage_limit?` before `transient?`, and `@usage_re` includes the generic
  phrase `try again`. A persistent 5xx/gateway error whose body contains "try again" is
  classified `:usage_limit`, whose retry arm has **no cap and no wall-clock bound** — it sleeps
  15 min and retries forever, silently stalling the whole run.
  *Fix:* gate usage-limit on `api_error_status == 429` (and/or subtype); drop bare `try again`
  from `@usage_re`; cap the usage-wait loop with a cumulative wall-clock ceiling.

### P1 — the quality lever: gate on house-style, not just green
- **[HIGH] Accept gate ignores analysis score AND compile warnings** (`cycle.ex:77`).
  A green, mutant-killing solution ships even with no `@moduledoc`/`@spec`/`@doc`, lines >98
  cols, or compile warnings. Confirmed empirically: compilation 0.925 vs 0.991; families 089
  (promo) and 104 (connection-pool) ship with **zero `@spec`** and, for 089_001, a live warning.
  *Fix:* extend `accept?` to also require `compile_warnings == 0` and analysis subscore == full
  (moduledoc+spec+doc), feeding any shortfall into `repair_report` so the fixer adds the missing
  docs/specs or silences the warning before re-grading.
- **[MED] Solver prompt never states the house style** (`prompts.ex:108`). The model is neither
  told the rubric nor checked against it. *Fix:* add an explicit checklist to `base_solve` and
  `fix(:task)`: every public fn gets `@moduledoc`+`@spec`+`@doc`, ≤98 cols, no TODO, match
  `+0.0`/`-0.0` never bare `0.0` (kills the OTP-27 harness-warning smell). Mirror for harnesses.

### P2 — the mutation gate is weaker than it looks
- **[MED] Whole-module mutation gate** (`mutation.ex:64`, `:39`). One raise-mutant for the whole
  module is killed if the harness asserts **any one** function — so a harness that tests 1 of N
  public functions still passes. This is exactly the observed 095 case (`split/2` uncovered while
  the module gate passed). *Fix:* mutate each public function independently and require every
  per-function mutant to be killed — mirroring the (already correct) per-candidate FIM gate.
- **[LOW] Mutant "killed for the wrong reason"** (`mutation.ex:67`). A mutant that compile-fails,
  times out, or OOMs counts as `:killed`. *Fix:* score `:killed` only when the mutant grade shows
  `compiled == true AND (tests_failed>0 OR tests_errors>0)`; treat compile-fail/timeout as
  inconclusive, not a pass.
- **[LOW] `green?` counts excluded tests** (`evaluator.ex:109`). `tests_total>0` is satisfiable by
  skipped-only harnesses. *Fix:* require `tests_passed > 0` (executed assertions).

### P2 — yield left on the table
- **[HIGH] Variations never topped up** (`catalog.ex:214`, `:222`). Any single `_002` marks the
  base "done", so a batch that landed only 1–2 of 3 variations permanently leaves the rest
  ungenerated — and the hardcoded `b = n+1` slotting can't fill a gap anyway. *Fix:* base
  `needs_variations?` on the **count** of `NNN_00X_*_01` (X≥2) being < 3, generate only the
  missing slots into the next free index, and pass existing variation names into the prompt.
- **[LOW] FIM never topped up to the cap** (`catalog.ex:215`). One `_02` marks the parent done.
  *Fix:* `needs_fim?` = `count_existing_fim < fim_max_per_task`; exclude already-used targets.
- **[MED] Unfixable FIM candidates re-selected & re-rejected every run** (`fim.ex:49`, `:202`).
  Matches the observed "same 095 `_02` id 3× in runs.jsonl". Wastes 2 Opus calls per run forever,
  and rejected candidates collide on the same `_0d` id (overwriting each other's logs). *Fix:*
  persist a negative marker (`.fim_rejected` sidecar or runs.jsonl scan) and exclude rejected
  `(task_id, target)` pairs; give each attempted candidate a unique log id.

### P3 — operational & correctness papercuts
- **[MED] `GEN_LIMIT` bounds only new bases, not backfill** (`catalog.ex:163`). `GEN_LIMIT=1`
  still fans backfill across all ~165 accepted `_01`s (hundreds of calls). *Fix:* apply the limit
  to combined work, or print a loud "backfill: N seeds — NOT bounded by GEN_LIMIT" header.
- **[MED] `--max-turns 20`, doc says 1** (`opus.ex:222`). Truncation hits `error_max_turns` and
  is retried with the **identical** prompt up to 5× (partial result discarded), instead of the
  "return ONLY complete `<file>` blocks" reminder. *Fix:* restore `--max-turns 1` or route
  `error_max_turns` through the reminder path and salvage an already-valid partial bundle.
- **[MED] Crash between promote and tasks.md insert orphans a variation** (`variations.ex:116`).
  Dir exists, catalog line doesn't, and `has_variations?` (disk-based) then reports done so it's
  never healed. *Fix:* on each run, reconcile promoted variation dirs against tasks.md headers
  (insert is already idempotent), independent of `has_variations?`.
- **[MED] No in-flow variation dedup** (`variations.ex:26`). Distinctness is prompt-only; two
  cosmetically-different variations both pass and promote. *Fix:* require 3 differing one-line
  axes up front, and/or reject a variation whose public fn set equals a sibling's.
- **[LOW] `sanitize_file_body` only unwraps a first-line fence** (`reply.ex:41`). Leading prose +
  fences survive; for `prompt.md` (never compiled) they ship verbatim. *Fix:* strip leading
  non-fence lines / unwrap any single fenced region; reject a body still holding a lone ``` line.
- **[LOW] Empty/refusal reply with `is_error:false` logged as success** (`opus.ex:122`). Only
  fails downstream at validation; pollutes cost/yield metrics. *Fix:* detect zero-`<file>` /
  refusal replies and return `:refusal` distinctly.

---

## 2b. Fixes applied (2026-07-02)

Four improvements were implemented and validated end-to-end on a fresh idea (131, Streaming
JSON Parser): base + 3 variations all accepted first-try under the new gates, with the base
meeting the house style (moduledoc/spec/doc, zero warnings) and the per-function mutation gate
passing. All 83 `test/gen_task` unit tests green.

| Finding(s) | Fix | Where |
|---|---|---|
| #1 usage-limit hang | Tightened `@usage_re` (dropped bare "try again"/"resets at"); capped the usage-wait loop at `GEN_USAGE_MAX_WAIT_MS` (default 6 h) so a misclassified transient can't hang the run. | `opus.ex`, `config.ex` |
| #3 #4 #12 #14 #15 house-style/warnings not gated | New quality gate: a green base/variation must also have `@moduledoc`+`@spec`+`@doc`, no TODO, and **zero compile warnings**, else it's repaired then rejected; the solver + fix + harness prompts now state the house style (incl. `+0.0` matching). Disable with `GEN_SKIP_QUALITY_GATE=1`. | `cycle.ex`, `evaluator.ex`, `prompts.ex`, `config.ex` |
| #10 #21 weak whole-module mutation | Base/variation gate now mutates **each public function independently** and requires every one killed (whole-module fallback only when no public fns parse). Disable with `GEN_SKIP_PER_FN_MUTATION=1`. | `mutation.ex`, `cycle.ex` |
| #2 #6 #20 no top-up; #8 #11 unfixable FIM re-attempted | `needs_variations?`/`needs_fim?` are now **count-based** (fill until 3 variations / `fim_max` FIM); variations fill only free slots and are told existing names; FIM excludes already-covered targets and targets permanently rejected on a prior run (`logs/fim_rejected.jsonl`); rejected candidates no longer collide on one log id. | `catalog.ex`, `variations.ex`, `fim.ex`, `cycle_log.ex`, `prompts.ex`, `reply.ex` |

Still open (not in this batch): #9 (`--max-turns 20` vs doc's 1), #5 (crash-orphaned variation vs
`tasks.md`), #13 (in-flow variation dedup), #16 (leading-prose fence in `prompt.md`), #17
(empty/refusal logged as success), #18/#19 (mutant "killed for wrong reason"; `green?` counts
excluded tests). And the pre-existing corpus failure **`032_002`** (hand-authored).

## 3. Recommended order of work

1. **Fix the usage-limit hang** (P1 bug) — tiny, prevents silent overnight stalls.
2. **Gate on `compile_warnings == 0` + house-style, feed into repair** (P1 quality) — biggest
   measured lever (compilation 0.925 → ~1.0), plus strengthen the solver prompt.
3. **Per-public-function mutation** (P2) — closes the real coverage hole the gate is meant to guard.
4. **Top-up variations & FIM + stop re-attempting unfixable FIM** (P2 yield).
5. **Papercuts** (P3) — `GEN_LIMIT`+backfill, `--max-turns`, orphan reconciliation, prompt fences.

Pre-existing, separate from the loop: **fix `032_002` (1/8 failing)** so `validate.exs` goes fully
green.
