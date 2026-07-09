# 10 — Quality-assurance audit: gaps in solution quality, test strength, and prompt correctness

Date: 2026-07-07. Scope: full harness — evaluator (`lib/eval_task/`), generation loop
(`lib/gen_task/`), gate scripts, docs 01–09, plus a hands-on 16-task sample across all five
shapes and corpus-wide scans (3,744 gradable dirs). Verification basis for the sample: every
file read in full; 27 tasks executed green under Elixir 1.20.2/OTP 29; all sampled FIM
completions spliced and compiled with `--warnings-as-errors`.

Headline: executable health is genuinely good (27/27 executed green, zero warnings, median
sample grade B+/A-), but the gates verify **execution**, not **meaning**. Nothing checks that
a harness asserts only what the prompt states, that a candidate test suite discriminates
anything, or that two variations differ. Several gold solutions with real bugs or grader
contamination are already in the corpus.

---

## 1. Tier 1 — defects that put wrong gold data into the corpus

### 1.1 Prompt↔harness consistency has zero gates; the repair loop launders mismatches
- No gate anywhere compares harness assertions to prompt text. If Step A's harness asserts
  behavior the prompt never states, the blind solve fails, and the fixer — who sees the
  failing tests (`cycle.ex:168-189`) but may never edit `prompt.md` (`reply.ex:94-109`) —
  bends the solution to match the harness. The task is then **accepted with an
  under-specified or wrong prompt**.
- Confirmed instances from the sample:
  - `001_001` harness passes `cleanup_interval_ms: :infinity` (test_harness.exs:26); prompt
    describes the option only as an interval in ms. Corpus scan: **50 harnesses** pass
    `*_interval_ms: :infinity`, **36** `send(pid, :cleanup)` pinning an internal message
    name, **62** reach into internals via `:sys.get_state`. This template-propagated hidden
    contract is the single most systematic prompt-completeness defect (~10% of harnesses).
  - `623_001` prompt lists a minimum stemmer; the harness requires "-er" stripping +
    double-consonant dedup that only the reference implements. A spec-minimum solution fails.
  - `016_001` requires non-numeric params to fall back to defaults; prompt covers only
    missing/<1.
  - `wt_131_004` prompt's own example (`last_index == 0` past EOF) **contradicts** the gold
    harness (`== 5`, test_harness.exs:151-156) — a spec-following candidate suite fails.
- Fixes, in order of strength:
  1. **Second-independent-blind-solve gate**: before acceptance, a second blind solve from
     `prompt.md` alone must also go green (catches under-specification and overfit tests in
     one gate). Cheapest high-leverage addition.
  2. LLM-judge pass on accepted tasks: "list every harness assertion not entailed by
     prompt.md."
  3. Prompt-template rule (`prompts.ex` base_task/variations): "every assertion in the
     harness must be justified by an explicit sentence in prompt.md."
  4. Static lint on generated harnesses: reject `:sys.get_state`, `send(pid, :internal_msg)`
     to non-API messages, `assert inspect(...) ==`, exact exception-message matches.
  5. Flag (from `logs/attempts/`) every accepted task whose first blind attempt failed on
     assertions and was repaired solution-only — that population is where laundered
     mismatches live. The data is already captured.

### 1.2 Variations skip solver blindness entirely
- Base tasks preserve blindness (Step B sees prompt.md only, `base.ex:62-64`); variations
  co-author prompt + harness + solution in **one call** (`prompts.ex:154-197`,
  `variations.ex:167-172`). ~3/4 of all `_01` tasks never demonstrate "solvable from the
  prompt alone". Fix: discard the co-authored solution and run a blind Step-B solve from the
  variation prompt (one extra call per variation).

### 1.3 Vacuous-test acceptance paths (four distinct holes)
- **Mutation testing covers only `:fim` shape** (`validate.exs:167`). Single, multifile,
  `wt_`, `tfim_` harnesses have no non-vacuousness check beyond "reference passes".
- **`wt_` grading is unsound for its purpose**: a candidate test suite is graded solely
  green-against-the-correct-impl (`runner.ex:229-242`); `assert true` scores 1.0. Coverage
  "inherited from the parent gate" is **false for backfill seeds** — `warn_if_vacuous_seed`
  (cli.ex:194-233) warns and derives anyway, so known-vacuous harnesses become gold labels.
- **`tfim` accepts assertion-free tests**: reconstruction green iff reference passes
  (`runner.ex:250-277`); bundle parents gated by a bare `assert` **regex**
  (`test_fim.ex:148-157`) that `assert true` satisfies.
- **Raise-mutants prove invocation, not assertions** (`mutation.ex`): `assert is_map(f(x))`
  kills the raise mutant while asserting nothing. Plus: `green?` needs only 1 passing test
  (`evaluator.ex:112-118`); `init/1` blanket-exempted from mutation (`mutation.ex:243-248`)
  including GenServer `init/1` in a GenServer-heavy corpus; bundles get whole-solution
  mutation only (`mutation.ex:215-222`).
- Fixes: extend raise-body mutation to **all shapes** in `validate.exs` default mode; for
  `wt_`/`tfim_`, grade candidates against a **mutated** reference (candidate tests must fail
  it); add a small semantic-mutant set (`<`↔`<=`, ±1 on int literals, `:ok`↔`:error`) as a
  scored signal; floor `tests_total >= max(3, public_fn_count)`; scope the `init/1`
  exemption to actual Plug modules; per-module mutation for bundles.

### 1.4 Buggy or contaminated golds already in the corpus (from a 16-task sample)
- `105_001` debouncer: **real stale-timer race** (cancel_timer result ignored, no
  generation check, solution.ex:62,71-77) — and the `105_001_..._03` FIM prompt then
  **specifies the buggy behavior as the requirement**, canonizing the race as gold.
- `102_001`: gold solution's comment names the harness's `FakeRepo` test double
  (solution.ex:262-264) — grader contamination in an SFT completion; FakeRepo ignores
  `order_by`/`limit`/`select`, making the "chronological order" requirement untestable and
  imposing a hidden query-API contract.
- `623_001`: two empirically vacuous tests (all tf-idf scores 0.0; pass only via map-order +
  stable-sort accident, masked by pinned `seed: 0`); stemmer maps `meetings`→`meeting` but
  `meeting`→`meet`.
- If a 16-task sample surfaced three, the corpus rate is material → a stratified human/LLM
  review pass is justified (see §4.4).

### 1.5 The "perfect" gate has a rounding hole
- `overall` is rounded to 2 places before `perfect?` checks `>= 1.0`
  (`analysis.ex:129`, `validate.exs:130-133`): raw ≥ 0.995 passes as perfect — a ≥140-test
  harness with one failure validates. Gate on unrounded invariants:
  `tests_failed == 0 && tests_errors == 0 && warnings == 0 && analysis == max`.
- Related: `tests_total == 0` still banks analysis+compilation (up to 0.30); `score/3`
  never consults `tests_errors` (`analysis.ex:104-123`).

### 1.6 Repairs can silently delete failing tests
- A fix reply may replace `test_harness.exs` wholesale; nothing compares `tests_total` or
  test names across attempts. Deleting the failing test is the fixer's path of least
  resistance and passes every gate. Fix: reject/flag repairs that reduce test count or drop
  named tests (reuse `TestFim.test_blocks/1`).

### 1.7 FIM-specific correctness holes
- A candidate containing `defmodule` bypasses the skeleton **verbatim** (`fim.ex:65-66`) —
  "fill only this hole" unenforced; may rewrite other functions.
- Deterministic-skeleton fallback (`fim.ex:256-270` `rescue _`) silently ships the model's
  hand-written skeleton, which is never checked to equal parent-minus-target — the promoted
  prompt's "every other function intact" claim can be false. Log the fallback + AST-compare
  skeleton to parent.
- The FIM prose description (part 1 of prompt.md) is validated by nothing — grading uses
  only the fenced skeleton. A wrong description with a correct skeleton promotes.
- `extract_candidate` takes the first fenced block (`fim.ex:76-80`) — grabs explanatory
  snippets when present.

---

## 2. Tier 2 — evaluator robustness

### 2.1 Results are forgeable; no sandbox
- Solutions compile and run **inside the evaluator BEAM** with full privileges
  (`runner.ex:312-324`); verdicts are scraped as "last stdout line starting with `{`"
  (`run_all.exs:101-106`, `validate.exs:203-214`). A candidate can print its own perfect
  grade and `System.halt(0)`, redefine `EvalTask.FailureCollector`, or monkeypatch ExUnit.
  Fine for a trusted corpus, fatal the moment alternate-model/benchmark grading starts
  (which docs/07 plans). Fix: emit JSON to an out-of-band file path passed as an argument
  (or nonce the line), and run candidates unprivileged.

### 2.2 Flake forgiveness should be flake detection
- `validate.exs:100-121` re-runs test-failure suspects serially and counts a serial pass as
  pass — a 50%-flaky harness survives ~75% of validations. Three same-morning `run_all`
  sweeps disagreed on which tfim dirs failed (009_002_04, 031_003_03, 031_004_11,
  625_001_02 are current suspects). Fix: write recovered flakes to a ledger, quarantine
  repeat offenders, add `--stability N` (N consecutive all-pass runs). The deeper cure for
  the debounce/TTL families is the corpus's own best pattern: injected fake clocks (already
  used by 130 harnesses) instead of `Process.sleep` (136 harnesses).

### 2.3 Missing timeouts and silent skips
- `validate.exs:232` and `run_all.exs:68` run evals with infinite timeouts (one hang stalls
  the sweep); `mint_repairs.exs:149-153` grades **rejected attempts** — the population most
  likely to hang — with no `timeout` wrapper. `GenTask.Evaluator.grade` already does it
  right; copy it.
- `validate.exs:27` silently drops tasks whose `solution.ex` is missing; discovery returns
  `nil` for unclassifiable dirs — corpus rot is invisible. Report them as failures.
- Bundle parser silently drops non-matching `<file>` blocks (`bundle.ex:10-24`) — verify
  full input consumption.
- `Kernel.ParallelCompiler.compile` error tuples crash a bare `{:ok, ...}` match
  (`runner.ex:348`), burying real compiler errors in a truncated MatchError inspect.
- `validate_harnesses.sh` claims to stub modules but never does; its "OK_NEEDS_MODULE"
  whitelists typo'd module references. Delete or fix — it invites misplaced trust.

### 2.4 Operational nits
- `grade_sample.exs:6-9` decodes whole stdout, not the last JSON line — any harness
  `IO.puts` breaks it.
- Empty/refusal LLM replies with exit 0 classify `:ok` (`opus.ex:134-146`), burning a
  reminder retry with misleading wording (docs/05 #17, still open).
- Contract-violating fix replies regrade identical bytes (`cycle.ex:180-183`) —
  deterministic identical failure, wasted attempts.
- Mutation-construction exceptions masquerade as `{:survived, ...}` "vacuous harness"
  (`mutation.ex:50-56`) — misleading reject reasons + unfixable repair loops.
- Acceptance provenance unrecorded: gates are env-skippable
  (`GEN_SKIP_QUALITY_GATE`/`GEN_SKIP_PER_FN_MUTATION`) but the ledger doesn't record which
  gates were active; `mutant_failed: true` is hardcoded on acceptance even when mutation was
  skipped (`cycle.ex:86-94`, `write_test.ex:153`, `test_fim.ex:326`).

---

## 3. Tier 3 — idiomaticity and style enforcement

### 3.1 No formatter gate; corpus is not canonically formatted
- **3,989 of ~4,340** solution/harness files differ from `Code.format_string!` output under
  the local toolchain (multi-line map updates the formatter collapses, aligned-column
  assignments in multifile golds, guard-indentation drift). There is no
  `mix format --check-formatted` anywhere in the gates, and `.formatter.exs` inputs cover
  `tasks/**/*.exs` but **not** `tasks/**/*.ex`. Toolchain drift compounds it (machine runs
  1.20.2; README pins 1.17+; formatter rules changed in between).
- Fix: pin the toolchain (`.tool-versions`), decide the canonical format version, add a
  format check to `quality_shortfall` and `validate.exs`, and one-shot reformat the corpus
  (formatter output *is* the idiomatic standard — that churn improves the training data).

### 3.2 Analysis checks are corpus-wide regex probes, trivially gameable
- `has_moduledoc` is `String.contains?`; one `@spec`/`@doc` anywhere satisfies an 8-function
  module (`analysis.ex:51-53`) while `@house_style` demands them on **every** public
  function — trained models learn "one @spec is enough". Bundles are joined into one string,
  so one documented file covers six (`analysis.ex:68-70`). Collected metrics
  (`pipe_chain_count`, `max_line_length`…) are computed and never scored.
- Fix: AST-walk per public function (machinery exists in `Mutation.public_functions/1`);
  require `@moduledoc` be a non-`false` string; per-file bundle analysis; run line-length/
  TODO checks on `test_harness.exs` too (harness style is currently ungated); apply at least
  the warnings gate to FIM golds (`quality_shortfall` runs only in the `:task` cycle).
- Credo is a declared dep ("for scoring solutions", mix.exs) that has **never run**
  (`analysis.ex:17-19` admits it). Wire `Credo.run` on staged solutions with a curated rule
  set, or drop the dep.
- The SQLi regex is broken (alternation precedence, uppercase-only, single-line) — replace
  or drop; it's a 1-point security theater.

### 3.3 Concrete idiom debt found in golds (candidates for prompt rules + static checks)
- 80 solutions use soft-deprecated `unless` (`mix format --migrate` rewrites it).
- One-tuples as control values (`{:not_found}`, `{:invalid}` — 102_001).
- `@type t :: nil | map()` (077_002) and `:ets.tid()` for named tables (043_001) — wrong or
  garbage-tier specs pass the "has @spec" probe; 110 specs use bare `any()`.
- Reinvented stdlib: `Enum.reduce` where `Map.reject/2`/`Enum.sum_by` exist (003_002 family).
- Internals exposed as `@doc false` public defs instead of `defp` (623_001).
- **Zero doctests corpus-wide**; property tests exist only in the 075 family. Neither is
  ever requested by the prompt templates.
- 306 solutions use `cond do` — worth a Credo-style review for pattern-match refactors.

### 3.4 Prompt-template upgrades (`prompts.ex`)
- Add an explicit harness checklist: ≥1 negative/error-path test per public function,
  boundary tests, `describe` grouping; add OTP-conventions bullets (`@impl true`, no
  blocking `init/1`, `handle_info` catch-all, call timeouts); request doctests and (where
  apt) one property test.
- Share one harness-rule constant between `base_task`, `variations`, and
  `WriteTest.prompt_md` — the variations template silently dropped the tmp-file-uniqueness
  rule (docs/08 §2.5 failure class recurring).
- Fix the `:fim` fix-prompt contradiction ("fix prompt.md if skeleton wrong" vs "do NOT
  return prompt.md", `prompts.ex:362-364`).
- Rotate 3–5 exemplar triplets of different shapes (pure module / GenServer / behaviour /
  binary parsing) instead of the single rate-limiter exemplar that pulls every task toward
  GenServer + fake-clock shape.
- `fim_select`: filter parsed candidates against `Mutation.all_functions/1` (hallucinated
  targets currently proceed to generation); stop preferring private helpers the gate then
  rejects as inconclusive.
- Delete or mark historical the dead `tasks/*.md` meta-prompts; fix docs/04 §8–10 provenance.

---

## 4. Tier 4 — dataset-level assurance

### 4.1 Dedup, leakage, and split strategy: absent
- Variation distinctness is prompt-instruction-only against **titles** (docs/05 #13 open).
  Found: 50 FIM subtask solutions byte-identical across different variations.
- By construction one `_01` fans its solution text verbatim into fim/wt/tfim examples —
  cross-shape leakage is unquantified and no family-keyed train/val split is documented.
- Fix (deterministic, zero LLM): normalized-AST hash + shingle-Jaccard pass in
  `dataset_stats.exs`; reject variations whose public-fn set equals a sibling's; document
  family-level split keys (`NNN` task number as the grouping key).

### 4.2 Register monoculture was multiplied, not fixed
- docs/07 called prompt-register monoculture "the biggest SFT-quality problem"; the corpus
  then grew 2.7× in exactly the monocultural shapes (2,318 tfim prompts all opening
  "# Fill in"). Productize the register metric in `dataset_stats.exs` (first-N-words
  histogram, constraint-phrase counts), then do the docs/07 §5.1 rewrite pass.

### 4.3 Captured value sitting unused; no CI; no committed evidence
- 552 attempt chains under `logs/attempts/` and 0 minted `repair_*` dirs —
  `mint_repairs.exs` (add the timeout first, §2.3) has never run.
- No CI, no hooks; `results/` and `logs/` gitignored — the entire audit trail is one
  `rm -rf` from gone and no committed artifact proves the corpus's state. Commit
  `summary_*.txt` + `perfect_failures.txt` (tiny) and/or add a CI job running
  `validate.exs`; back up `logs/`.
- `.gen_staging/` holds 2,660 leftover dirs — add GC.

### 4.4 No human/LLM review loop
- BACKFILL Phase 2 ("spot-review for sensibility/house-style") is an unchecked box; the
  §1.4 hit rate says it matters. Build `scripts/review_sample.exs`: stratified random
  sample (shape × family × date), present prompt+solution+harness, record verdicts to a
  committed ledger; optionally an LLM-judge prompt-alignment pass (the one gate class
  nothing covers).

---

## 5. Work log — DONE as of 2026-07-08

All changes below are **uncommitted on `main`** (verify with `git status --short`; ask the
user before committing). Verified: `mix test` → 168 passed; full-corpus default gate →
3,745/3,745 perfect; `--mutants` → 597/597 killed. Elixir 1.20.2 / OTP 29 on this machine.

### 5.1 `scripts/validate.exs` (rewritten)
- `perfect?/1` now requires the RAW invariants — `compiled == true`,
  `compile_warnings == 0`, `tests_passed > 0`, `tests_failed == 0`, `tests_errors == 0` —
  in addition to `overall >= 1.0`. Closes the §1.5 rounding hole (raw ≥ 0.995 used to
  round to 1.0 and pass).
- `split_corpus/2`: task dirs with a missing `solution.ex`, and dirs `Discovery`
  cannot classify, are reported as `corpus-integrity` failures (they used to vanish
  silently). Currently zero such dirs.
- Every eval subprocess runs under `timeout --signal=KILL` (`EVAL_TIMEOUT_S`, default
  240s); exit 137 is reported as a kill, other non-zero exits as crashes. A
  non-JSON `{`-prefixed stdout line now fails that ONE task instead of crashing the
  whole sweep (`decode_json/1`).
- Flake filter: recovered flakes are appended to `logs/flaky.jsonl`
  (`{"task":…,"ts":…,"detail":…}`) and still pass; `--stability N` requires N
  consecutive serial passes to recover (default 1).
- New `--mutants` mode: for shapes `:single`, `:multifile`, `:write_test`, builds a
  whole-solution raise-mutant via `GenTask.Mutation.mutate/1` and requires the harness
  to FAIL or ERROR against it. Verdict logic (`mutant_verdict/3`): kill = mutant
  compiled AND (`tests_failed > 0` OR `tests_errors > 0`). **The errors clause is
  essential**: the 074 family are macro modules — a gutted `defmacro` raises at
  harness COMPILE time, grading as `tests_errors: 1, tests_total: 0`; since the same
  harness is green against the reference, that error is caused by the mutation and IS
  a kill. `:fim` is covered by `--fim`; `:test_fim` is skipped (its per-block
  isolation gate runs at mint time; see step R7 for the open bundle-tfim gap).
- New `--only "glob1,glob2"` filter on task names, works with every mode. Used for
  smoke runs: `elixir scripts/validate.exs --mutants --only "074_00*,wt_074*"`.

### 5.2 `lib/eval_task/analysis.ex`
- `score/3`: `overall` hard-fails to 0.0 when `tests_total == 0` or `tests_errors > 0`
  (used to bank analysis+compilation ≤ 0.3 with zero tests). Reasons list explains both.
- Tests: `test/eval_task/analysis_test.exs` (2 new tests at the end).

### 5.3 `lib/gen_task/mutation.ex`
- `gate_base_whole/3` (via new `gate_base_whole_graded/4`): when `mutate/1` returns the
  source unchanged (parse failure / empty bundle), the reject reason is now
  "a raise-mutant could not be constructed … no harness edit can fix this" instead of
  the lie "tests still pass after every function body is replaced by raise" (which sent
  the fixer on unfixable repair loops, §2.4/audit 2.9).
- `init/1` per-fn mutation exemption is scoped to Plug modules only
  (`plug_module?/1`, public `@doc false` for tests): a GenServer's `init/1` is now
  mutation-checked. NOTE: this makes the per-fn gate stricter for FUTURE generation;
  it does not re-judge the existing corpus.
- Tests: `test/gen_task/mutation_test.exs` (`plug_module?/1`, unbuildable-mutant reason).

### 5.4 `lib/gen_task/cycle.ex`
- `run/3` reduce-loop now caches `{grade, decision}` when a fix returns byte-identical
  files — no regrade, no per-fn mutation re-sweep on identical input (audit 2.11).
- New `guard_test_deletion/3` (public `@doc false`): a fix whose `test_harness.exs` has
  FEWER `test`/`property` blocks (counted at any nesting via
  `~r/^\s*(?:test|property)\s+"/m`, so flat→describe restructuring is safe) is rejected
  as a contract violation — deleting a failing test is not a repair (§1.6).
- Tests: new `test/gen_task/cycle_test.exs` (5 tests).

### 5.5 `lib/gen_task/prompts.ex`
- `fix/3`: the unconditional "do NOT return prompt.md" contradicted the `:fim` contract
  ("prompt.md — only if the skeleton was wrong"); the rule line is now per-kind, and the
  `:task` variant states the no-test-deletion rule (matches 5.4's enforcement).

### 5.6 `lib/eval_task/runner.ex`
- `compile_bundle/1` handles `{:error, errors, _}` from `Kernel.ParallelCompiler.compile`
  and surfaces real diagnostics (`diagnostics_to_errors/1`) — a bare `{:ok,…}` match used
  to bury them in a truncated MatchError inspect.
- Tier-B kit/migration compile uses new `compile_or_raise!/2` (raises with real
  diagnostics; the tier-B rescue upstream reports compiled:false). Migration WARNINGS
  are still not counted — deliberately unchanged (would re-grade the 11 multifile tasks).

### 5.7 Scripts
- `run_all.exs` — eval under `timeout --signal=KILL` (`EVAL_TIMEOUT_S`); TIMEOUT status
  distinct from CRASH; `crash_json/2` takes the message.
- `mint_repairs.exs` — grading of captured attempts (the population MOST likely to hang)
  now runs under the same kill; unparsable output decodes to `%{}` (not green → not
  minted) instead of crashing.
- `grade_sample.exs` — decodes the LAST `{`-prefixed line like every other consumer.

### 5.8 Full-corpus verification results (2026-07-08, this machine)
- Default gate: **3,745/3,745 perfect**. Two flakes recovered serially and logged:
  `104_004_usage_recycling_connection_pool_01` (1/8 failed under load),
  `tfim_012_003_inventory_stock_event_sourced_aggregate_10` (1/24). Note these are
  DIFFERENT tasks than the 2026-07-07-morning suspects
  (`tfim_009_002_*_04`, `tfim_031_003_*_03`, `tfim_031_004_*_11`, `tfim_625_001_*_02`) —
  the timing-sensitive population is larger than any single run reveals.
- `--mutants`: **597/597 killed** (288 single + 11 multifile + 298 wt_). The corpus has
  NO whole-solution-vacuous harness. Remaining unmeasured: assertion tightness
  (semantic mutants, R10) and tfim per-block strength for bundle parents (R7).
- `--fim` smoke on `003_002*`: pass. Full `--fim` sweep not re-run this session (was
  green on 2026-07-07; nothing in this batch changes FIM mutation semantics except the
  shared verdict helper, which only WIDENS kills).

### 5.9 Full blind-solve sweep COMPLETE (2026-07-08) — R4a corpus screen results
- `mix run scripts/screen_blind_solve.exs` ran the full corpus screen: model=opus,
  sequential, 00:20–11:55 (~11.5h), 300 calls, $58.08, 0 transport errors.
  **299/299 `_01` tasks screened — 198 GREEN (66%), 101 RED (34%).**
  Ledger: `logs/screen_blind.jsonl` (latest entry per task wins; `--report`
  summarizes without calls). Only uncommitted change to the script itself: mode
  bit (`chmod +x`).
- Canaries behaved exactly as designed: `001_001` RED, `016_001` RED (screen is not
  too weak), `623_001` GREEN (the R2c fix→screen loop held on the full run).
- `001_001` is the one task with two ledger entries: the R5b prompt backfill changed
  its sha and it auto-re-screened — resume/re-screen machinery works. Its re-screen
  is the sweep's most instructive result: the blind solution now handles the FIXED
  hidden contracts (`:infinity`, `send :cleanup`) and fails on the NEXT one —
  `assert map_size(state.keys) == 0` (test_harness.exs:176) hard-codes an internal
  state field name the prompt never mentions (the harness comment even admits "The
  state is implementation-dependent" two lines later). The §1.1/R5-deferred
  `:sys.get_state` debt is now EMPIRICALLY confirmed to bite blind solves.
- Failure buckets (machine-classified from `first_failure`; full triage plan in R12):

  | bucket | n | examples |
  |---|---|---|
  | internal-state shape asserts (`key :x not found`, via `:sys.get_state`) | 8 | 001_001, 005_004, 007_003, 010_004, 020_002, 023_001, 023_003, 097_002 |
  | direct named-ETS / persistent_term access from the harness | 5 | 042_003, 042_004, 044_004, 045_001, 045_002 |
  | undisclosed helper-API surface (`… is undefined or private`) | 8 | 016_002/3/4, 017_003, 024_002/3/4, 074_003 |
  | named-process / multi-instance start contracts (`failed to start child`, `:noproc`) | 9 | 041_001–004, 020_003/4, 025_002, 045_003/4 |
  | harness defines collaborator modules the blind solver also defined (`{:invalid, %ExUnit.TestModule{…}}`) | 3 | 071_002/3/4 |
  | candidate failed to compile | 13 | Phoenix self-containment: 016_001, 019_001 (likely 005_001); solver slips: 025_003, 036_002, 074_002, 075_004, 077_004, 101_001, 110_002, 134_001/2; crash: 061_001 |
  | harness itself failed to load against the candidate | 2 | 017_001, 018_001 (harness `use SoftCrudWeb.ConnCase` + `~p` routes — scaffolding the prompt never asks for) |
  | behavioral/semantic assertion mismatches (everything else) | 53 | 007_001–004 (SMA/WMA math), 020_001 (413 vs 422), 035_002/4 (which exception), 086_001/2 (`cart.items == %{}` pins internal representation), 074_001/4 (asserts exact failure-message text), 100_001 (URL-encoding %20), 031_003, 013_003, … |

- Two notable single-task findings:
  - `105_001` RED is good-news/bad-news: the blind solution reintroduced the EXACT
    stale-timer race R2a fixed, and the new regression test caught it — the test
    discriminates (good). But "The delay is real" (prompt.md:31) did not get an
    independent solver to ref-matching; prompt.md:45 ("cancel/replace them") could
    gain a hint: a cancelled timer may already have fired — guard fires with a ref.
    The prompt arguably ENTAILS the behavior, so this may be a keep-as-hard-task.
  - `061_001` timed out/crashed and left `erl_crash.dump` (7.6MB, repo root,
    02:28, "runtime terminating during boot") — delete the dump, re-screen the task.
- Caveat for reading the 198 greens: a green blind solve proves solvable-from-prompt;
  it does NOT prove the harness asserts everything the prompt states (the
  under-testing direction is still only covered by mutation gates).

### 5.10 R12a prompt backfills (IN PROGRESS, interrupted) + out-of-tokens hardening (2026-07-08)

**R12a state.** "Additional interface contract" sections were added (uncommitted) to the
11 undisclosed-helper-API / harness-collaborator prompts — 016_002/3/4, 017_003,
024_002/3/4, 071_002/3/4, 074_003 — parent `_01` AND `wt_` copies (22 prompt.md files;
no FIM/tfim embeds affected — verified by the R12a session via grep). The sha-keyed
re-screen (`logs/rescreen_r12a.log`) was INTERRUPTED by token exhaustion after 6/11:
- **GREEN (backfill worked, de-quarantined): 016_002, 016_003, 016_004, 017_003.**
- The remaining 5 were re-screened after the hardening below (`logs/rescreen_r12a2.log`,
  all 5 RED) and triaged with a second round of prompt fixes:
  - **024_002/3/4 — KEEP, solver-weak (prompts fine).** All three fail identically
    post-backfill (`KeyError :secret|:providers not found in: []`): the blind solver
    falls into the Plug.Router init-opts→dispatch threading trap (route bodies see
    dispatch's `[]`, not the opts given to `init/1`). The prompts fully document the
    option lists and the harness uses the standard `Router.call(conn, Router.init(opts))`
    contract — everything is entailed; passing needs the `builder_opts()`/`call/2`-
    override idiom. Same hard-task class as the R12e regex-sigil cluster.
  - **071_002/3/4 — prompt gap FOUND and fixed.** The harness `setup_all` calls
    `Factory.start()`; the gold defines it (named Agent for sequence counters) but the
    variation prompts never mention it — the base 071_001 prompt DOES ("started once
    (e.g., in `Factory.start/0` …)"), so the variation template dropped it. Every blind
    solve died in `setup_all` (`{:invalid, %ExUnit.TestModule{…}}`). Added a
    `Factory.start/0` bullet to the interface-contract section (3 parents + 3 wt_).
  - **074_003 — TWO stacked prompt gaps found and fixed.** The harness requires plain
    runtime variants of ALL three macros; the prompt (even with the first backfill's
    `next_message/2` bullet) disclosed neither `process_exits/2`'s pinned failure
    phrases (`"did not terminate"` + `inspect(pid)` + liveness boolean — the prompt only
    said "show the pid, whether it is still alive, and how long it waited", which the
    blind candidate did and still failed) nor `no_message/1` at all (surfaced by the
    NEXT re-screen once the first fix unblocked it). Both bullets added (parent + wt_).
    Lesson for R12a: enumerate EVERY undisclosed symbol the harness references in one
    pass (`grep AssertHelpers\.` etc.) instead of peeling one gap per $0.19 re-screen.
  Re-screen results (`logs/rescreen_r12a3.log`, `_r12a4.log`): **071_002, 071_003,
  071_004, 074_003 all GREEN — de-quarantined.** Families re-validated ALL PERFECT
  after every prompt edit.
**R12a CLOSED**: all 11 bucket tasks resolved — 8 de-quarantined via prompt backfills
(016_002/3/4, 017_003, 071_002/3/4, 074_003), 3 triaged-keep as legitimately hard
(024_002/3/4, Plug.Router opts-threading — prompts entail everything). Quarantine:
97 (post-R12e) − 8 greens = **89 red in the ledger, of which 024×3 + the R12e keeps
are documented triaged-keep residue**. Remaining fronts: R12b (13 internal-state
harness rewrites), R12c (Phoenix family decision), R12d (~53 behavioral triage).
- Screen script upgrade: blind candidates are now SAVED to
  `logs/screen_candidates/<task>__<sha8>.ex` (they used to be deleted after grading,
  leaving only a 200-char failure snippet — today's triage had to re-derive failures
  inferentially).

**Out-of-tokens hardening (the interruption's root cause, now fixed).** The transport's
15-min usage-wait loop worked as designed (7 attempts logged riding out the window), but
the sweep ran as a foreground child of an interactive session that itself ran out of
tokens and was dropped — killing the sweep mid-wait. Changes:
- `Opus` `@usage_re` now also matches credit-exhaustion wording (`out of credits`,
  `credit balance`, `insufficient credits`) so it can never route to `{:refusal, …}`.
- `GEN_USAGE_MAX_WAIT_MS` default changed **6 h → 0 = unlimited**: running out of tokens
  is a normal condition; the call retries every 15 min until the 5-hour window resets,
  however long that takes (set > 0 to restore a fail-fast cap). Wait warnings now include
  cumulative minutes waited. docs/04 §11 + env table updated.
- `screen_blind_solve.exs`: if a capped run DOES exhaust (`{:usage_limit, :exhausted}`),
  the sweep stops cleanly with a resume hint instead of churning every remaining task
  through its own multi-hour wait.
- **New `scripts/run_detached.sh <logfile> <cmd…>`** (setsid + nohup): launch ALL
  LLM sweeps through it so they survive the launching session being dropped — this, not
  the wait loop, was the actual failure. Tests: 2 new in `opus_test.exs` (credit wording;
  unlimited-wait rides out 30 consecutive limit replies). `mix test`: 190 passed.

### 5.11 R12b + R12c + R2b + R10 executed (2026-07-08 evening, uncommitted)

**R12b CLOSED (13/13 dirs).** Per-family outcomes (all validated perfect + mutants,
all edits count-checked exact replacements, wt_/tfim carriers synced):
- Harness rewrites to observable-behavior asserts: 001_001 (exemplar: `:cleanup` +
  follow-up API call synchronizes AND detects crash), 005_004 (poll documented
  `publish/3` matched-count for async :DOWN), 007_003 (window growth/cap semantics
  prove `max_window_size` without reading state), 010_004 (documented `keys/1`),
  023_001/023_003 (replay expired keys through the API), 042_003/042_004
  (NAME-AGNOSTIC persistent_term/ETS diff: snapshot before start, assert this
  instance's registrations gone after stop — plus a prompt sentence making the
  terminate-cleanup obligation explicit), 045_001/045_002 (setup used an
  UNDOCUMENTED `table_name:`/`name: nil` start that forced a hidden discovery
  mechanism — now `start_supervised!` with documented defaults; acid-tested with
  naive blind-style implementations that previously failed).
- Prompt-side: 097_002 (exception TYPE for missing `:username` documented —
  rewriting the test would have violated the mutation gate).
- No defect (solver-slip class, keep): 020_002 (Plug opts-threading, same as 024),
  044_004 (blind candidate was self-inconsistent; three different blind-style
  implementations all pass 12/12; residual noted: `assert :ok = increment` pins an
  undocumented return).
**R12c CLOSED (4/4).** 016_001/017_001/018_001/019_001 harnesses now dispatch via
`Plug.Test` straight to the Router — ConnCase/Endpoint/verified-routes out of the
candidate-facing surface; ConnTest conveniences shimmed locally (`get/post/put/
delete`, `json_response`, `sigil_p`) so every TEST BODY stayed byte-identical (=
tfim gold blocks untouched; 016_001's 10 tfim embeds updated by exact preamble
replacement only). Each task got `manifest.exs` (`:phoenix_conncase` explicit —
inference can't see tier B in a Plug.Test harness) + prompt "Additional interface
contract" naming Router/Repo/schema (016_001 also documents the `:updated_at`
fixture field). Runner fix: tfim reconstruction now COPIES THE PARENT'S
manifest.exs into its staging dir (`grade_harness_against_module/3`) — archetype
must survive reconstruction.
**R2b CLOSED.** 102_001 migrated off FakeRepo onto a real SQLite repo via a new
**repo-only tier**: archetype `:ecto_repo` (manifest-only, never inferred) →
`Runner.compile_tier_repo` boots kit Repo + bundle migrations, no web modules
(`PhoenixKit.render_repo/5`). Harness: sandbox `start_owner!(shared: true)` (the
GenServer queries from its own process). FakeRepo deleted from all 6 carriers;
tfim_04's gold block updated (it contains the restart test). order_by/filtering
now enforced by a real query engine. Prompt states the provided-repo contract +
`priv/repo/migrations/` path requirement.
**Blind-screen structural fix.** The screen asked EVERY task for one `solution.ex`
— a multifile blind solver couldn't know the repo's inner-`<file>`-bundle
convention, so tier-B tasks were unsolvable in the screen BY CONSTRUCTION (016_001
red showed `PaginatedList.Repo is not available`: plain-file candidate → graded as
:single → no kit). Now: `Prompts.base_solve/2` (`:multifile` asks for one <file>
block per app source file), `Reply.validate_bundle_answer/1`, screen assembles the
blocks into bundle form. The pre-fix Phoenix re-screen reds in `rescreen_r12bc.log`
are ARTIFACTS — re-screen those four after the sweep.
**R10 DONE (machinery + tests; corpus sweep launched).** `Mutation.semantic_mutants/2`
(first-order: comparison swap, int ±1 spread-capped at 40/module, `:ok`↔`:error`,
bool flip; doc/string/typespec-safe; parse-verified; deterministic) +
`validate.exs --semantic-mutants` report-only mode (histogram + weakest-20 +
`logs/semantic_mutants.jsonl`). First signal: `003_002_gcra_01` kills only 12/22
(54.5%) semantic mutants despite a 100% raise-mutant kill — assertion tightness is
the real gap, exactly as §1.3 predicted. Full-corpus sweep: `logs/semantic_sweep.log`.
**R11 progress.** `.githooks/pre-push` (mix test + touched-family perfect+mutant
gates; installed via `git config core.hooksPath .githooks`) and
`.github/workflows/validate.yml` (push/PR: test + --mutants with a Postgres
service; weekly + dispatch: full sweep + --fim; uploads results/ as artifact).
**R12d machinery.** `scripts/triage_screen.exs` — LLM-judge per quarantined red
("quote the prompt sentence that entails the failing assertion — or say none"),
(task, sha)-keyed ledger `logs/screen_triage.jsonl`, `--report` mode; judge sees
prompt + first_failure + saved candidate. Human sign-off stays mandatory for
prompt edits (cascade invariant #5).
**Ops note.** The R10 subagent + this session hit the token-window limit mid-run;
the detached re-screen rode it out exactly as designed (15-min waits, attempt 15+,
~210 min) — the §5.10 hardening is validated in production.

### 5.12 R12d executed: judge triage + 31 backfills (2026-07-08 night, uncommitted)

**Triage.** `scripts/triage_screen.exs` ran over all 79 quarantined reds (model=opus,
0 errors, `logs/screen_triage.jsonl`): **47 ENTAILED** (prompt justifies the failing
assertion — solver-weak, keep as legitimately hard tasks) / **32 PROMPT GAPS** with a
proposed missing-contract sentence each.

**Backfills: 31 of 32 applied** (5 parallel agents, every judge proposal VERIFIED
against gold+harness before applying — four judge inaccuracies caught and corrected
from source: 006_002 raises ArgumentError (judge claimed exit tuple), 061_004's
budget claim refuted (weights only), 070_003/4's recorded shape is
`{:exception, exception, stacktrace}`, and 007_004's premise was inverted — the real
gaps were a missing slack-guard rule + a post-alert freeze the prompt described as
auto-re-learn). Classes:
- 22 mechanical disclosures (pinned atoms/exit reasons/message substrings/return
  values/option shapes) appended as "## Additional interface contract" bullets,
  parent + wt_ prompt embeds.
- 5 prompt↔gold contradictions corrected in place (007_004 freeze+slack, 010_004
  per-call-window filters-not-evicts, 014_001 off-loop processing, 073_001
  Process.put stash, 096_001 script/style content dropped).
- 086_001/086_002: cart struct's public fields documented (the struct IS the API).
- 005_003: harness-side R12b-style rewrite (`t.subs == []` reach-in → public-API
  poll + link-crash detection; targeted mutant check: DOWN-clause raise killed by
  exactly the rewritten test).
- 018_001: gold behavior changed 200 → **201 on create** (idiomatic Phoenix);
  controller `put_status(:created)`, harness create asserts, prompt bullet, wt_
  byte-copies re-synced.
**Deferred [decision]: 001_004_penalty_escalation** — the judge's proposal amounts to
re-specifying decay/cooldown interaction semantics; that is a spec design choice,
not a disclosure. Needs the user: either canonize the gold's exact semantics
(cooldown until strike_time + ladder[strike_index]; last-strike timestamp advances
per removed strike) in the prompt, or simplify the gold. Until then: quarantined.

All 31 families re-validated ALL PERFECT (+ mutants where executable files changed).
Every prompt edit changes the screen sha → the next plain screen run re-screens all
of them; 005_003 (harness-only) needs `--rescreen`.

**R10 corpus measurement (complete).** 597 tasks, 12,960 semantic mutants, **71.4%
killed** (mean per-task 0.731; 1,224 non-compiling dropped). Right-leaning histogram
(141 tasks ≥ 0.9) with a real weak tail: 22 tasks < 0.4, worst `075_004` 0/7.
Ledger: `logs/semantic_mutants.jsonl` (per-task survivor labels). Follow-up
work-list: tighten the weak-tail harnesses; mind equivalent-mutant noise.

**Overnight re-screen results (2026-07-09, post-commit 5f29311).**
- 31 backfilled prompts re-screened: **23 GREEN (de-quarantined)**, 8 red on a
  DIFFERENT, deeper layer each (stacked-gaps pattern; e.g. 007_004 now fails
  "invalid options raise at start_link"; 074_002 was a solver compile slip).
- 005_003 harness fix re-screened: **GREEN**.
- **Quarantine: 299 screened → 244 green / 55 red = 47 documented keeps + 8
  round-2 candidates** (round-2 triage: `logs/triage_round2.log`,
  `logs/screen_triage.jsonl` — sha-keyed, auto-re-triaged). Down from 101 reds
  at the start of 2026-07-08.
- `--stability 3` full sweep: ALL PERFECT. `logs/flaky.jsonl` aggregation:
  8 distinct tasks, none with ≥2 occurrences yet — R9 needs runs across days
  before quarantining anyone.

**R12d rounds 2–3 (2026-07-09, closing the loop).** Round 2: 5 of the 8 survivors
backfilled (3 more judge inaccuracies corrected from source — 074_001's real
predicate is "truthy except non-true atoms"; 073_001's exact TRUNCATE form + the
repo.query!/3-on-module mechanism; 086_001's judge chased entry shapes) →
071_001 + 074_001 GREEN. The 3 remaining repeat-offenders then got a
COMPREHENSIVE one-pass audit (every harness assertion vs prompt, all gaps at
once — the §5.10 lesson applied): 007_004 (+6 bullets: start_link/0, warmup
boundary, Welford-during-warmup, non-numeric FunctionClauseError, reset
semantics, frozen check shape), 073_001 (+4: transaction strategy mechanics,
clean-without-start no-op, strategy switching), 086_001 (root cause found at
last: `add_item` returns `{:ok, cart}` — the success shape was never specified;
+4 bullets) → **ALL THREE GREEN**.

**FINAL SCREEN STATE: 299 screened — 249 GREEN / 50 RED**, every red a
judge-confirmed entailed-keep (prompt justifies the assertion; task is
legitimately hard — the intended difficulty distribution) except the one open
[decision] 001_004. Campaign total: 101 reds → 50 keeps; 51 tasks de-quarantined
via 60+ verified prompt/harness/gold fixes across R12a–R12d.

### 5.13 Session 2026-07-09: R11 mint + 001_004 resolved + R6 executed

- **R11 repair pairs MINTED (3/3)**: `repair_074_003_*_01_00`, `_01_01`,
  `repair_079_003_*_01_00` — 552 chains → 63 candidates → 3 survived double
  verification (fix green AND broken red against the accepted harness).
  Validated perfect + mutants. The 060 unverified are quality/mutation-gate
  rejects that were still green — they cannot teach a test-fix (expected).
- **001_004 [decision] RESOLVED — canonized (option a)**: the gold's
  "decay forgives cooldowns" semantics are coherent; 5 bullets added to
  parent + wt_ prompts (lazy decay w/ exact-boundary + reference-time-advance,
  decay-cancels-cooldown, cooldown end = strike_time + retry_after_ms,
  rejected requests don't consume window slots). NOTE: the R12d judge's
  proposed sentence was BACKWARDS (claimed cooldown persists independent of
  decay) — the fifth judge inaccuracy of the campaign; always derive from
  source. Family perfect + mutants; blind re-screen GREEN (11/11).
  **Screen: 250/299 green, 49 reds — ALL documented keeps. Loop fully closed.**
- **R6 EXECUTED** — corpus reformatted to `Code.format_string!` canonical form
  (2,545 files: 390 executable + 1,777 prompt embeds + trailing-newline
  normalization), `scripts/format_corpus.exs` written (`--check` gate in CI +
  pre-push), `Evaluator.autoformat/1` keeps future generation canonical,
  `mix format --check-formatted` green repo-wide. Full detail in the R6 section.
  Evidence: final full perfect + mutants + fim suite green over the settled tree.
- **triage_screen.exs --report** stale-gap debt fixed: gap verdicts whose prompt
  sha changed on disk (or whose task re-screened green) now count as
  stale/resolved — report shows 0 open gaps / 29 resolved / 50 keeps.
Known cosmetic debt: `triage_screen.exs --report` lists ledger gaps without
filtering out ones whose prompt sha has since changed (already-applied
backfills still print) — polish when next touched.

---

## 6. Remaining work — step-by-step plan (R1–R12)

Each step is self-contained: files, approach, acceptance criteria, gotchas.
Steps marked **[decision]** need the user's choice before implementation.

**Status as of 2026-07-09: the R1–R12 plan is COMPLETE.** R1–R8, R10–R12 done
(including the R11 repair-pair minting and the 001_004 decision, §5.13); R6 done
2026-07-09. The only standing item is **R9 (flake quarantine)**, which by design
needs `--stability` runs spread across days — aggregate `logs/flaky.jsonl` and
quarantine repeat offenders as the data accumulates. Follow-up work-lists that
outlive the plan: the R10 semantic-mutant weak tail (22 tasks < 0.4 kill rate in
`logs/semantic_mutants.jsonl`), the docs/07 register-monoculture rewrite (§4.2),
and the §4.4 stratified review loop beyond the blind-screen population.

Original priority order for reference: R1 → R12 → R6 → R9 → R10 → R11.

### R1. Commit the current batch + gate evidence ✅ DONE 2026-07-08
- The §5 batch + docs/10 sweep report were committed by the user (`7ecaf5d`
  "Overnight report", includes the script `chmod +x`).
- `logs/screen_blind.jsonl` force-added past the `logs/` gitignore rule and
  committed (`0c77e6c`) — the R12 input is now version-controlled.
- Acceptance verified post-commit: `mix test` 188 passed;
  `elixir scripts/validate.exs --only "001_001*"` ALL PERFECT.
- Still open (folded into R11): committing `results/summary_*.txt` +
  `perfect_failures.txt` from the NEXT full validate run.

### R2. Fix the four known-bad golds (§1.4) — mostly deterministic edits
Work one task family at a time; after EACH family run
`elixir scripts/validate.exs --only "<family>*"` AND `--mutants --only "<family>*"`.

**R2a. `105_001_genserver_based_debouncer` — stale-timer race (REAL bug in gold).
✅ DONE 2026-07-08.** Fix: each arm stores `{ref, timer, func}` (`ref` from
`make_ref/0`), timers send `{:fire, key, ref}`, and `handle_info/2` drops any fire
whose ref no longer matches — a stale fire can no longer run the replacement func
early. All 11 family carriers updated: parent solution + harness (new suspension-based
regression test "a stale timer message cannot run the replacement func early" —
deterministic via `:sys.suspend/resume` message-ordering, not sleep-racing), FIM
`_02`/`_03` gold functions + skeletons + prose (the `_03` prose that MANDATED the race
is rewritten to specify ref-matching), FIM `_04` skeleton, wt_ solution/harness/prompt
embed, and the three tfim prompt embeds (module + harness text; reconstruction reads
the embedded harness, so it carries the new test too). Verified: family green under
perfect + mutants; the OLD solution graded against the new harness fails EXACTLY the
regression test (10/11); the fixed solution passes 11/11 in 3 consecutive runs.
Original details for reference:**
- Bug: `solution.ex:62` ignores `Process.cancel_timer/1`'s result and never flushes an
  already-delivered `{:fire, key}`; `handle_info({:fire, key}, …)` (solution.ex:71-77)
  runs whatever func is CURRENTLY stored. Sequence: timer fires (message queued) →
  new `debounce(key, new_func)` cast processed → queued `:fire` processed → `new_func`
  runs immediately, violating prompt.md:31-32 ("The delay is real").
- Fix pattern: store a unique ref per arm — `%{key => {ref, func, timer}}`; send
  `{:fire, key, ref}`; in `handle_info`, run only if the stored ref matches.
- CASCADE (critical, this is why the fix is fiddly):
  1. `tasks/105_001_genserver_based_debouncer_01/solution.ex` — the fix.
  2. `_01/test_harness.exs` — consider adding a regression test (hard without a fake
     clock; the family is wall-clock — acceptable to skip, note it).
  3. FIM children `105_001_*_02/03/04…`: their `prompt.md` embeds the ENTIRE parent
     module minus one function, and `_03`'s prose SPECIFIES the buggy behavior
     (prompt.md:11-14 "If the key still had a pending entry, run its func"). Each
     child's prompt.md skeleton must be rebuilt from the fixed module and the prose
     corrected; each child's `solution.ex` (the single function) must match the fixed
     implementation of its hole.
  4. `wt_105_001_*/solution.ex` is a byte-copy of the parent solution — copy the fixed
     file. Its `test_harness.exs` is the parent harness — update if 2 changed.
  5. `tfim_105_001_*` dirs embed parent module+harness in prompt.md — same rebuild.
  6. Find all children: `ls tasks/ | grep 105_001`.
- Acceptance: `validate --only "*105_001*"` and `--mutants --only "*105_001*"` green;
  manually re-read `_03/prompt.md` to confirm the prose no longer mandates the race.

**R2b. `102_001_genserver_based_state_machine_with_persistence` — grader contamination.
✅ Minimum fix DONE 2026-07-08.**
- The comment naming `FakeRepo` (solution.ex:262-264) is rewritten to state the
  contract ("pattern-matching on the whole struct keeps the query portable across any
  injected repo implementation") in all SIX copies: parent + wt_ `solution.ex`, and
  the module text embedded in `wt_`/three `tfim_` `prompt.md`s. Remaining `FakeRepo`
  mentions live only in harness/test text, where the double legitimately exists.
  Family verified green (perfect + mutants). The BIGGER fix below is still open:
- **[decision]** Bigger fix (harness's FakeRepo ignores order_by/limit/select, making
  the "chronological order" requirement untestable): either make FakeRepo honor
  `order_by`/`limit`/`select` on its `all/2`/`one/2`, or migrate the task to the
  SQLite tier-B kit. Recommend the faithful-fake option (self-contained, no infra).
- Same cascade rules as R2a (this is a multifile bundle; children: `grep 102_001`).

**R2c. `623_001_mini_elasticsearch_like_inverted_index` — vacuous tests + stemmer.
✅ DONE 2026-07-08 (test names kept stable so tfim skeletons stay valid).**
- The two all-zero-idf tests ("title boost…", "term in multiple fields…") each gained
  a third document WITHOUT the query term (idf = log(3/2) > 0), assert the exact
  ordered id list, and assert `hd.score > last.score` — an all-zero tie now fails by
  construction instead of passing by map-order accident.
- The stemming test no longer requires un-spec'd "-er"/double-consonant stemming:
  "running"/"runner" became "walking"/"walked" + "jumps"/"jumped", derivable from the
  prompt's "-ing"/"-ed"/"-s" alone; ids asserted as a sorted set (scores tie at equal
  tf, so ordering is deliberately not asserted there).
- Synced all FIVE carriers of the harness text: parent + wt_ `test_harness.exs`, and
  the three tfim `prompt.md` embeds (none of the tfim gold blocks target the edited
  tests — verified before editing). Family green under perfect + mutants.
- Still open (needs a prompt change first): the reference stemmer's
  `meetings`→`meeting` vs `meeting`→`meet` inconsistency remains untested; normalize
  only if the prompt is extended to specify fixpoint stripping.

**R2d. `wt_131_004_resumable_streaming_json_array_parser_with_error_budget` — spec
contradicts gold. ✅ DONE 2026-07-08.**
- prompt.md:68-69 said `:last_index` is 0 when `resume_from` is past the end; the gold
  harness asserts `== 5` (test_harness.exs:162) matching the impl (skipped lines count
  as examined). Fixed the sentence in BOTH copies — `131_004_*_01/prompt.md` and
  `wt_131_004_*/prompt.md` (grep confirmed no FIM/tfim child embeds it). Family
  verified: `validate --only "*131_004*"` and `--mutants --only "*131_004*"` green.

### R3. Stop deriving `wt_`/`tfim_` from vacuous seeds ✅ DONE 2026-07-08
- `warn_if_vacuous_seed` became `GenTask.CLI.vacuous_seed?/3` (public `@doc false`,
  cache-seeded unit-testable): the cached per-fn raise-mutant verdict
  (`logs/seed_verdicts.jsonl`, content-hash keyed) now GATES the `:derived`-stage
  works — a vacuous backfill seed is excluded from `run_derived_works`, and one
  `SKIPPED (vacuous seed harness — fix test_harness.exs …)` outcome per withheld
  work type is printed and recorded to `logs/runs.jsonl` (`skip_derived_works/2`).
  FIM is deliberately NOT gated here (gate_fim rejects per candidate). A crashed
  self-check derives + logs (infra failures must not freeze corpus growth). Fixing
  the harness changes the hash → next run re-checks and unblocks automatically.
- `GenTask.Work.vacuous_blocked/1` + a `BLOCKED (vacuous seed harness …)` section in
  `scripts/work_status.exs` surface withheld seeds corpus-wide, so the
  status → generate → status loop stays explainable (blocked ≠ silently pending).
- Tests: `test/gen_task/cli_vacuous_seed_test.exs` (4 tests: cached vacuous blocks,
  cached clean derives, content-key invalidation, no cross-task leakage).
  End-to-end verified with a PLANTED vacuous verdict for
  `001_003_hierarchical_limiter_01`: work_status showed the BLOCKED row
  (`test_fim: 1`), a `GEN_DRY_RUN=1 GEN_ONLY=backfill GEN_LIMIT=1` run logged the
  blocking warning and emitted exactly one SKIPPED outcome (write_test had 0
  missing → correctly no skip line), ledgers restored from backup afterwards.
- NOTE: zero vacuous verdicts exist in today's ledger and the `--mutants` sweep was
  clean, so nothing is currently blocked — this gate protects FUTURE derivation.

### R4. Blind re-solve screen — the prompt↔harness consistency check
**✅ FULLY DONE 2026-07-08: machinery + canaries + full 299-task sweep (198 green /
101 RED, $58.08 — results in §5.9). The output is the R12 quarantine triage.**

Implemented:
- **R4a**: `scripts/screen_blind_solve.exs` — one blind solve per `_01`
  (`Prompts.base_solve` + `Cycle.generate`, NO repair loop), graded via
  `Evaluator.grade` with the candidate as override. Verdicts append to
  `logs/screen_blind.jsonl` keyed by sha256(prompt.md): interrupted runs resume,
  fixed prompts auto-re-screen. Flags: `--only/--limit/--model/--rescreen/--report`.
- **R4b**: `GenTask.Variations.build_variation` now DISCARDS the co-authored
  solution and blind-re-solves from the variation prompt
  (`Variations.blind_solution/3`; `GEN_SKIP_VARIATION_BLIND=1` opts out; one extra
  call per variation). The gen+validate+remind helper is now shared
  `Cycle.generate/6` (Base delegates). Both prompt templates gained the
  assertion-justification rule ("a solver reading ONLY prompt.md must pass every
  test; never assert internal state or undocumented option values"); the variations
  template also regained the process-unique tmp-path rule it had dropped (audit 1.4).
- Tests: `test/gen_task/blind_solve_test.exs` (5, fake transport — blind solver sees
  prompt only, reminder-retry fires once, contract exhaustion propagates).

Canary run (model=opus, 3 real calls, 2026-07-08):
- `001_001_rate_limiter_01` → **RED**, and with the EXACT predicted failure: the
  blind solution crashed on `:erlang.send_after(:infinity, …) :badarg` — the harness's
  hidden `cleanup_interval_ms: :infinity` contract (§1.1). Screen works.
- `016_001_paginated_list_endpoint_01` → **RED** (controller does not compile against
  the undisclosed PhoenixKit scaffolding — the §1.1 self-containment gap).
- `623_001_mini_elasticsearch_like_inverted_index_01` → **GREEN** — before the R2c fix
  this failed on un-spec'd "-er" stemming; an independent solver now passes from the
  prompt alone. Fix→screen loop closed.

Full sweep ran 2026-07-08 (§5.9). The prediction "the `:infinity` family is the
known bulk" was WRONG in an informative way: R5b's prompt backfill fixed that layer
before the sweep, and the reds that remain are the layers BEHIND it — internal-state
shape asserts, undisclosed helper APIs, and behavioral ambiguity (see the §5.9
bucket table and R12). Original plan for reference:
The highest-leverage remaining item (§1.1, §1.2). Two parts:

**R4a. Corpus screen (one-off audit).** New `scripts/screen_blind_solve.exs`:
- For every `_01` task (`EvalTask.Discovery.all/0`, shapes `:single` + `:multifile`,
  ~299 dirs): call the solver with ONLY `prompt.md` (reuse
  `GenTask.Prompts.base_solve/1` + `GenTask.Cycle.opus/5` — transport, usage logging,
  and reply parsing already exist), grade the candidate against the task's harness via
  `GenTask.Evaluator.grade/3` with the candidate as override solution.
- Output: `logs/screen_blind.jsonl` — one line per task:
  `{task, green, tests_failed, first_failure, ts}`. FAILURES QUARANTINE, never delete:
  a blind-solve failure means EITHER an under-specified prompt (hidden requirement) OR
  a too-weak solver — a human (or stronger model) must look. Print a summary table.
- Cost: ~299 solver calls, one attempt each (no repair loop — repairs would defeat
  the point). **[decision]** which model + whether to also screen FIM prompts.
- Prediction from the hands-on sample: `001_001` (`:infinity` hidden contract),
  `623_001` (stemmer), `016_001` (non-numeric param fallback) should FAIL the screen —
  use them as canaries: if the screen passes them, the screen is too weak (solver may
  be pattern-matching the reference from its training data; consider temperature or a
  different model).
- ORDER: run AFTER R2/R5 prompt fixes to avoid re-flagging known issues, or before to
  measure baseline — recommend before-and-after on the canaries, full sweep after.

**R4b. Pipeline screen (permanent).** In `lib/gen_task/variations.ex` (~line 167-172,
where the co-authored triplet is parsed): discard the model's `solution.ex`, run a
blind Step-B solve from `vN/prompt.md` (mirroring `base.ex:62-64`), and feed THAT
through the normal cycle. One extra LLM call per variation; kills the §1.2 asymmetry.
Also add to `prompts.ex` `base_task`/`variations` harness rules: "every assertion in
test_harness.exs must be justified by an explicit sentence in prompt.md".

### R5. Harness anti-pattern lint + hidden-contract backfill
**✅ R5a DONE + R5b prompt-side DONE 2026-07-08; :sys.get_state rewrites deferred.**
`scripts/lint_harnesses.exs` (report; `--fix-prompts` applies the backfill; `--only`
scoping; idempotent per BULLET so new lint findings extend existing sections).
Detection subtleties learned: the trigger check needs `~r/:cleanup\b/` — a substring
check false-matches inside the OPTION name `:cleanup_interval_ms`; interval-key regex
is deliberately narrow so `timeout: :infinity`/`max_uses: :infinity` (different
semantics) aren't misflagged. Applied: 13 parents + wt_ copies got the `:infinity`
contract; 16 parents + wt_ copies got the `:cleanup`/`:sweep` manual-trigger
contract ("## Additional interface contract" section; parent = appended, wt_ =
inserted before "## Module under test"). Report is now CLEAN of fixable items;
affected families re-validate perfect; the blind-screen ledger is content-keyed so
these prompts auto-re-screen. REMAINING (report-only): 62 dirs with `:sys.get_state`
asserts — fixing means rewriting tests to assert observable behavior, cascading into
tfim gold blocks. The 2026-07-08 blind sweep surfaced WHICH ones actually bite:
8 state-shape + 5 direct-ETS/persistent_term reds (§5.9 table) — that 13-dir subset
is now R12b, the prioritized front of this queue. Original plan:
**R5a. Lint (deterministic, report-only first).** New `scripts/lint_harnesses.exs`
scanning every `test_harness.exs` (and tfim prompt-embedded harnesses if cheap):
- `:sys.get_state` (62 harnesses), `send(pid, :internal_atom)` where the atom is not
  in the prompt (36 have `send(_, :cleanup)`), setup opts with `:infinity` where the
  prompt does not say `:infinity` (50), `assert inspect(…) ==`, assertions on full
  exception message strings.
- Output a per-task CSV/JSONL + counts. Wire the counts into `scripts/dataset_stats.exs`
  later.
**R5b. Backfill [decision: prompt-side vs harness-side].** For the `:infinity`/
`send(:cleanup)`/`:sys.get_state` template family the audit recommends fixing the
PROMPT (add the sentence stating the contract: "the interval option also accepts
`:infinity` meaning never; the sweep can be triggered manually by sending `:cleanup`")
— cheaper than harness surgery and preserves green. But note the cascade: `wt_`
prompt.md embeds the parent spec (`lib/gen_task/write_test.ex:99-126` builds it), and
FIM/tfim children embed module/harness text — grep per family before editing.
`:sys.get_state` asserts are better fixed HARNESS-side (assert observable behavior
instead); that re-opens tfim children whose gold block is the offending test.

### R6. Formatter gate + toolchain pin
**✅ DONE 2026-07-09 — corpus reformatted + gates wired** (toolchain pin was done
2026-07-08: `.tool-versions` elixir 1.20.2-otp-29 / erlang 29.0.3 + README note).
- New `scripts/format_corpus.exs` (`--check` for CI, `--apply`, `--only`,
  `--category`). Canonical = `Code.format_string!` on the 1.20.2 pin. Categories:
  harness / module / bundle (per `<file>` part, wrapper bytes preserved) /
  fragment (fim+tfim solution.ex: dedent → format at `line_length: 98 - indent` →
  re-indent — the narrowed width matters: a just-fits line otherwise lands >98 at
  its embedded indentation, bit on tfim_104_004_04) / manifest / embeds
  (```elixir fences in fim/tfim/wt_ prompt.md; non-parsing fences left alone).
- **Exclusions by design**: `_01/prompt.md` (blind-screen ledger is sha-keyed —
  cosmetic churn would force a ~$58 full re-screen) and `repair_*/prompt.md`
  (the broken-code fence is captured attempt data).
- Verified formatting-safe BEFORE applying: eval-time FIM/tfim reconstruction is
  line-based on `# TODO`/def/end lines and never byte-compares to the parent;
  `build_skeleton`'s verbatim constraint is generation-time only. wt_ byte-copy
  invariant re-checked after apply: 0 mismatches.
- Measured deviation (much lower than the 2026-07-07 estimate, which counted
  trailing-newline noise): harness 3/600, module 196/589 (+153 more on the
  trailing-newline normalization), bundle 11/11, fragment 183/3148, embeds
  1777/3446 (8 fences needed the formatter's second pass to reach fixpoint).
- Full-file convention: exactly one trailing newline (mix format agreement);
  fragments keep their own convention (they are spliced, not standalone).
  `mint_repairs.exs` now writes trailing newlines (the 3 repair dirs were the
  offenders); lib/gen_task/{prompts,evaluator}.ex + lib/eval_task/runner.ex
  formatted → **`mix format --check-formatted` green repo-wide**, added to CI.
- Generation loop: new `Evaluator.autoformat/1` runs at `Cycle.run/3` entry and
  after every repair merge — graded bytes ARE promoted bytes; unparseable files
  pass through so the compile gate reports real diagnostics; a fix that formats
  to already-graded bytes reuses the cached decision. 6 unit tests.
- Gates wired: `format_corpus.exs --check` + `mix format --check-formatted` in CI
  (validate.yml); pre-push hook format-checks touched families.
- NOT done (deliberate): FIM candidates in the fim/wt/tfim GENERATION paths are
  not auto-formatted (they are fragments whose indentation context is the parent);
  the corpus-level `--check` would surface any future drift.
Original plan for reference:
- Pin the toolchain first: add `.tool-versions` (this machine: Elixir 1.20.2,
  OTP 29; README claims 1.17+ — align README).
- Measured 2026-07-07: 3,989 of ~4,340 corpus files are not canonical
  `Code.format_string!` output under 1.20 (real deviations — collapsed map updates,
  aligned columns — not just version drift). Sweep script exists in spirit at
  scratchpad `fmt_sweep.exs`; rewrite as `scripts/format_status.exs` (skip `<file`
  bundles or format each bundle part).
- One-shot reformat, THEN full `validate` + `--mutants` + `--fim` to prove no
  regression, THEN add `mix format --check-formatted`-equivalent to
  `Evaluator.quality_shortfall/1` (future generation) and a validate `--style` mode.
- GOTCHAS: (a) `.formatter.exs` `inputs` does NOT cover `tasks/**/*.ex` — extend it;
  (b) `<file>` bundles are not valid Elixir — format per parsed part via
  `EvalTask.Bundle.parse/1` and re-emit; (c) FIM child `prompt.md` embeds parent module
  text VERBATIM and `EvalTask.Fim`'s deterministic-skeleton path relies on the
  candidate appearing verbatim in the parent — reformatting parent `solution.ex`
  without regenerating child prompt skeletons breaks that invariant. Either reformat
  the embedded skeletons in the same pass or scope the reformat to `test_harness.exs` +
  `_01`/`wt_` `solution.ex` and verify `--fim` still passes.

### R7. Cheap deferred gate upgrades ✅ DONE 2026-07-08
- Bundle-parent tfim gate: `TestFim.asserting_block?/1` (AST) replaced the bare
  `assert`-word regex — `assert true`, comments, and strings no longer pass; an
  `assert`/`refute` needs a non-literal argument, behavioral macros
  (`assert_receive`/`assert_raise`/…) pass as-is (a module-reference requirement was
  deliberately NOT imposed: Phoenix golds use imported `conn` helpers with no module
  refs). 6 unit tests.
- FIM skeleton fallback: `deterministic_skeleton` now LOGS when the deterministic
  rebuild fails and only ships the model's hand-written skeleton after
  `Fim.skeleton_matches_parent?/3` proves (per-clause normalized AST) every function
  outside the hole is identical to the parent; divergence rejects the candidate.
  5 unit tests.
- `fim_select`: hallucinated `name/arity` targets are dropped against
  `Mutation.all_functions/1` before any generation call (bundles keep permissive
  behavior — they parse to `[]`).
Original plan for reference:
- Bundle-parent tfim gate: replace the bare `assert`-regex (`lib/gen_task/test_fim.ex:148-157`)
  with an AST check — the block must contain an assertion call whose args reference
  the module under test (parse via `Code.string_to_quoted`; blocks already `parses?/1`).
- FIM skeleton fallback (`lib/gen_task/fim.ex:256-270` `rescue _ -> ff`): log when the
  model's hand-written skeleton ships, and add an AST comparison — every function
  except the target must be structurally identical to the parent (compare
  `Macro.to_string` of sorted def bodies). Reject on mismatch.
- `fim_select` candidates: filter `parse_candidates` output against
  `GenTask.Mutation.all_functions(module_src)` so hallucinated `name/arity` targets
  don't burn generation calls (`lib/gen_task/fim.ex:186-204`).

### R8. Dedup / leakage stats ✅ DONE 2026-07-08
`dataset_stats.exs` gained a "DUPLICATION & LEAKAGE" section (+ `duplication` key in
`--json`): AST-hash exact-dup groups (54 found — cross-variation FIM functions;
wt_ byte-copies excluded by design), sibling-`_01` shingle-Jaccard near-dups
(**0 found** — variations genuinely differ), and within-family completion→prompt
leakage (**88%** — by construction) with the split recommendation printed: group
train/val by the leading idea number NNN. Original plan for reference:
- Exact-dup groups: normalized AST hash of every `solution.ex`
  (`Code.string_to_quoted |> Macro.to_string |> :erlang.md5`) — known baseline: 50 FIM
  single-function solutions byte-identical across DIFFERENT variations; wt_ dups are
  by design (byte-copies of parents) — exclude by shape.
- Near-dup variations: token-shingle Jaccard (k=8) between sibling variations'
  prompts and solutions; flag pairs > 0.85.
- Leakage: % of examples whose completion text appears verbatim inside another
  example's prompt (by construction ~every _01 solution appears in its fim/wt/tfim
  children — quantify and RECOMMEND the family split key: the leading `NNN` task
  number; document in README).
- Variation distinctness gate for the pipeline (docs/05 #13): reject a variation whose
  `public_functions(solution)` set equals the base's or a sibling's
  (`lib/gen_task/variations.ex:31-52`).

### R9. Flake quarantine follow-through
**First repeat offender FIXED 2026-07-09:** the 104_004 pool family hit ≥2 ledger
occurrences (parent 2026-07-07 + tfim_02 twice 2026-07-09, all "1/8 failed" under
sweep load, serial always green; 48 dedicated 12-way eval runs could NOT force
it). Fix was analytic: the harness's only wall-clock sensitivity was success-path
`checkout(…, 100)` deadlines + 500/1000ms receive windows — widened to
2_000/5_000 across all 7 harness carriers (no assertion weakened; the
`refute_received` short-sleep guards fail safe and stayed). Family green under
perfect + mutants + stability-3. The fake-clock pattern does NOT apply here:
blocked-checkout semantics need real concurrent waiting — deadline widening is
the right tool for this family class. Remaining suspects (all ≤1 occurrence —
keep accumulating across days):
- Known suspects (union of runs so far): `tfim_012_003_*_10`, `tfim_009_002_*_04`,
  `tfim_031_003_*_03`, `tfim_031_004_*_11`, `tfim_625_001_*_02` (×2 tasks),
  `wt_106_003`, `wt_045_003`.
- Run `elixir scripts/validate.exs --stability 3` a few times over a week;
  aggregate `logs/flaky.jsonl` (`jq -r .task logs/flaky.jsonl | sort | uniq -c`);
  fix repeat offenders by converting wall-clock waits to the injected fake-clock
  pattern (exemplar: `tasks/008_001_*/test_harness.exs` or `wt_010_001`'s Agent clock).
  A tfim flake means the PARENT harness block is timing-sensitive — fix the parent and
  cascade (same rules as R2a).
- **Ledger enriched 2026-07-09:** entries now carry a `failures` array (test name,
  module, first 300 chars of the assertion message) captured from the PARALLEL
  failure before the serial re-run discards it — a single occurrence now says WHERE
  the timing sensitivity is, and two occurrences on the same TEST are much stronger
  evidence than two on the same task. Per-test aggregation:
  `jq -r '"\(.task) :: \(.failures[]?.test // "?")"' logs/flaky.jsonl | sort | uniq -c`.
  (Entries before 2026-07-09 predate the field.) Verified end-to-end with a planted
  fails-once probe task (marker-file harness): recovered, gate green, entry carried
  the exact test + message; probe removed.

### R10. Semantic mutants (assertion tightness) — measurement first
- Extend `GenTask.Mutation` with a small operator set applied per public function:
  swap `<`/`<=` and `>`/`>=`, `+1`/`-1` on integer literals, `:ok`↔`:error` in
  returned tuples, boolean literal flip. Reuse the `mutate_fn/4` prewalk plumbing.
- Add `validate.exs --semantic-mutants` REPORT-ONLY (kill-rate per task, no gate):
  the corpus was never held to this bar; measure before deciding thresholds.
- This is the deterministic upgrade path for "raise-mutants prove invocation, not
  assertions" (§1.3) and would double as tfim per-block strength measurement.

### R11. CI + evidence + hygiene
**Partial 2026-07-08:** `.gen_staging` GC'd (2,660 leftover dirs, 122MB — verdicts
live in `logs/seed_verdicts.jsonl`, nothing recomputes); `mint_repairs --dry-run`
run: 552 chains → 63 candidate pairs → **3 verified mintable** (60 fail
double-verification because most captured rejections are quality/mutation-gate
rejects that were still GREEN — they cannot teach a test-fix); docs/05 erratum added
(flag renames, open-items pointer); `prompts.ex` moduledoc no longer claims the dead
`tasks/*.md` meta-prompts are live. Still open: CI job, committing gate evidence,
logs/ backup, minting the 3 pairs **[decision]**.
- CI job (GitHub Actions if the repo gets a remote, else a documented local
  pre-push hook): `mix test` + `elixir scripts/validate.exs --only "<changed
  families>"`, full sweep nightly. Needs the R6 toolchain pin.
- Back up `logs/` (552 captured attempt chains are one `rm -rf` from gone) and run
  `mix run scripts/mint_repairs.exs -- --dry-run` (now hang-safe after 5.7) to see the
  mintable repair-pair yield; then mint for real **[decision]**.
- GC `.gen_staging/` (2,660 leftover `*_seedmut` dirs).
- Update stale docs: docs/05 still documents `--fim-only`/`--green-only` flags
  (now `--fim`/`--green`); `prompts.ex:6` references dead `tasks/*.md` meta-prompts.
- NEW 2026-07-08: delete `erl_crash.dump` (7.6MB at repo root, left by 061_001's
  eval crash during the blind sweep) and gitignore `erl_crash.dump` if not covered.

### R12. Triage the 101-task blind-screen quarantine **[NEW — top work item]**
The sweep (§5.9) turned §1.1 from a hypothesis into a work-list. Every red means
EITHER an under-specified prompt OR a too-weak solver; the buckets have distinct fix
strategies and cascade profiles. Work bucket-by-bucket; the sha-keyed ledger
auto-re-screens any task whose prompt changes (each re-screen ≈ one opus call,
~$0.19 average).

**R12a. Deterministic prompt-side backfills. ✅ DONE 2026-07-08 — see §5.10:
8 de-quarantined via prompt backfills, 3 triaged-keep (024 family, solver-weak).**
- Undisclosed helper-API surface (8): the harness calls functions/arities the prompt
  never states (`CursorPaginator.paginate/1`, `WebhookReceiver.Store.get_event/2`,
  `AssertHelpers.next_message/2`, …). Fix: add the exact function signatures the
  harness uses to prompt.md (extend the `lint_harnesses.exs --fix-prompts`
  "Additional interface contract" mechanism — it is idempotent per bullet).
- Harness-defined collaborators (3, the 071 factory family): the harness defines
  `MyApp.User`/`MyApp.Post`/`FakeRepo`; the blind solver defined them too →
  `{:invalid, %ExUnit.TestModule{}}`. Fix: prompt sentence "assume these modules
  already exist (defined by the test environment); do NOT define them", listing the
  struct fields.
- Named-table names (subset of the ETS bucket where prompt-side is enough): where
  the harness reads a table whose NAME the prompt could simply state.
- Cascade: wt_ prompt embeds + tfim prompt embeds per family (invariant #5);
  re-run `validate --only` + `--mutants --only` per family, then re-screen.

**R12b. Harness-side rewrites — internal-state reach-ins (13 confirmed dirs).**
The R5 remainder, now empirically prioritized: 8 state-shape asserts
(001_001's `state.keys`, 005_004, 007_003, 010_004, 020_002, 023_001, 023_003,
097_002) + 5 direct ETS/persistent_term reach-ins (042_003/4, 044_004, 045_001/2).
Rewrite each offending test to assert observable behavior (the 001_001 harness
already documents the right pattern in its own comment: "verify by checking that
new requests for those keys work fresh"). CASCADES into tfim gold blocks when the
offending test IS a gold block — check per family before editing. The remaining
~49 of the 62 `:sys.get_state` dirs passed the blind screen; deprioritize them.

**R12c. Phoenix self-containment family [decision].**
016_001, 017_001, 018_001, 019_001 (and likely 005_001): candidates can't compile
(undisclosed scaffolding) or the HARNESS can't load (`use SoftCrudWeb.ConnCase`,
`~p` verified routes — infrastructure the prompt never asks the solver to write).
Decide once for the family: (a) prompts fully specify the scaffolding modules to
write, (b) tasks ship the scaffolding as provided context (multifile kit), or
(c) harnesses drop ConnCase/verified-routes for plain `Plug.Test`. Recommend (c)
where feasible — smallest cascade, keeps tasks self-contained.

**R12d. Behavioral/semantic ambiguity — human/LLM triage pass. ✅ DONE 2026-07-08
(see §5.12): 47 entailed-keep, 31/32 gaps backfilled, 001_004 deferred [decision].**
For each red: is the failing assertion ENTAILED by prompt.md? YES → solver-weak;
keep, mark triaged (105_001 is the exemplar: prompt entails it, blind solution had
the exact race the gold used to have — the test discriminates). NO → one-sentence
prompt backfill, then auto-re-screen. This is §4.4's review loop with a ready-made
work-list; batch it as an LLM-judge pass ("quote the prompt sentence that justifies
this failing assertion — or say none") with human sign-off on the "none" verdicts.
Recurring sub-patterns to rule on once, not 53 times: which-exception-class
(035_002/4), error-signaling convention — raise vs `{:error, _}` (006_002/3,
008_003), HTTP status choice (020_001), internal representation pinned by struct
field asserts (086_001/2 `cart.items == %{}`), exact failure-message text
(074_001/4), URL-encoding flavor (100_001).

**R12e. Cheap re-screens (solver-slip candidates). ✅ DONE 2026-07-08.**
Re-screened the 10 non-Phoenix compile failures + 061_001 with
`--rescreen --only …` (11 opus calls; log: `logs/rescreen_r12e.log`). Quarantine
101 → 97. Verdicts:
- **4 flipped GREEN** (one-shot solver slips, no longer quarantined): 005_001,
  075_004, 077_004, 110_002. The clock-in-struct-default hypothesis was checked
  first: both prompts describe the fn default as a start_link OPTION, so it was
  solver error, and indeed 110_002 passed on retry.
- **3 twice-RED, regex-sigil traps — solver-weak, prompts fine, KEEP**: 036_002
  (`~r/^(#{1,6})…/` — `#{}` interpolates in `~r//`), 134_001 + 134_002 (both wrote
  `~r{^\d{2}/\d{2}/\d{4}$}` — `{}` sigil delimiters do NOT nest braces, verified
  locally: quantifier `{2}` terminates the sigil → syntax error). A hard-task
  cluster, not a prompt defect.
- **1 twice-RED, solver-weak, KEEP**: 061_001 — prompt.md:10-11 explicitly requires
  crash → `{:error, reason}`; the blind solution let the exception propagate. The
  first run's eval crash did NOT recur (no new erl_crash.dump; old one deleted).
- **3 twice-RED with sharper diagnoses → R12d**: 025_003 (candidate `Map.put` on a
  keyword opts list — opts-shape convention), 074_002 (harness demands failure
  message contain "index 1", candidate printed "indexes 1 and 2" — the
  exact-message-text class), 101_001 (prompt defines window `[now - window_ms, now]`
  and says discard buckets "entirely before the window" ⇒ partially-overlapping
  buckets count, but the test expects an edge event NOT to count — genuine
  boundary-semantics ambiguity, one-sentence prompt fix candidate).

- Acceptance: quarantine shrinks to a documented residue of triaged-keep tasks
  (prompt entails the assertion; task is legitimately hard), recorded in a committed
  triage ledger (`logs/screen_triage.jsonl` or a docs table); every prompt-fixed
  family re-validates perfect + mutants and re-screens green.

---

## 7. Orientation for the next session (read this first)

### Key file map
| Thing | Where |
|---|---|
| Evaluator entry (per-task grade, JSON on stdout) | `scripts/eval_task.exs` → `lib/eval_task/cli.ex` → `lib/eval_task/runner.ex` |
| Scoring rubric + hard-fail rules | `lib/eval_task/analysis.ex` (`score/3`) |
| Shape detection (single/multifile/fim/wt/tfim) | `lib/eval_task/discovery.ex`, `cli.ex detect/2` |
| Corpus gate (perfect/green/fim/mutants/only/stability) | `scripts/validate.exs` |
| Generation loop cycle (stage→grade→gates→repair) | `lib/gen_task/cycle.ex` |
| Mutation gates (whole, per-fn, fim, tfim-isolation) | `lib/gen_task/mutation.ex` |
| LLM prompt templates | `lib/gen_task/prompts.ex` |
| Solver transport + usage ledger | `lib/gen_task/opus.ex`, `cycle.ex opus/5` |
| Work registry (what remains to generate) | `lib/gen_task/work.ex`, `scripts/work_status.exs` |
| Eval-under-timeout reference implementation | `lib/gen_task/evaluator.ex grade/3` |
| Blind-solve screen + ledger (§5.9, R12) | `scripts/screen_blind_solve.exs`, `logs/screen_blind.jsonl` |

### Invariants and gotchas (violating these has bitten before)
1. **`mix compile` before running any script** — scripts prepend `_build/*/ebin`; stale
   beams silently run old logic.
2. **Never write into `tasks/` from generation code** except via `Cycle.promote/3`;
   staging goes to `.gen_staging/` or tmp (`Evaluator.stage!/2` enforces this).
3. **Eval JSON contract**: consumers must decode the LAST stdout line starting with
   `{` — never the whole stdout.
4. **`tasks/017_001_*` needs Postgres** (`docker compose up -d db`); without it the
   task grades RED by design (never silently skipped). Docker socket was NOT
   accessible from the sandboxed session on 2026-07-08, yet the task passed the full
   sweep — a reachable Postgres apparently exists on this machine; if it starts
   failing, that is why.
5. **Editing any `_01` task cascades** to its `_0N` FIM children, `wt_` copy, and
   `tfim_` children (they embed the parent's module/harness text verbatim).
   `ls tasks/ | grep <NNN>_<VVV>` before and after; re-run `validate --only` on the
   whole family including derived prefixes: `--only "*<NNN>_<VVV>*"`.
6. **ExUnit seed is pinned to 0** in the runner — order-dependence and tie-order bugs
   are deterministic and thus INVISIBLE (see 623_001, §1.4). Randomized-seed audit is
   future work (docs/08 §2.4).
7. `wt_` dirs: `solution.ex` = byte-copy of parent module (BY DESIGN — it is the
   prompt context), `test_harness.exs` = the gold COMPLETION. Do not "dedup" these.
8. The `_02+`-suffix FIM dirs have NO harness — they reconstruct against the parent
   `_01`. `tfim_`/`wt_` prefixes are shape markers, not task numbers.

### Verification playbook (run after ANY change)
```bash
mix compile --warnings-as-errors && mix test          # 168 tests, ~1s
elixir scripts/validate.exs --only "<family>*"        # touched families, perfect gate
elixir scripts/validate.exs --mutants --only "<family>*"
elixir scripts/validate.exs                           # full corpus (~10 min, 16-way)
elixir scripts/validate.exs --mutants                 # 597 tasks (~4 min)
elixir scripts/validate.exs --fim                     # 830 FIM dirs (~10 min)
jq -r .task logs/flaky.jsonl | sort | uniq -c         # flake repeat offenders
mix run scripts/screen_blind_solve.exs --report       # blind-screen quarantine, no calls
```

### Launching LLM sweeps (screen/generate) — ALWAYS detach
Token allowance runs out routinely; the transport rides it out by sleeping 15 min per
attempt, indefinitely (`GEN_USAGE_MAX_WAIT_MS=0` default). That only helps if the sweep
survives its launching session — run every LLM-calling sweep through the detacher:
```bash
scripts/run_detached.sh logs/<name>.log mix run scripts/screen_blind_solve.exs [flags]
tail -f logs/<name>.log                               # follow progress
```
Both the screen ledger (sha-keyed) and the generation loop (work registry) resume for
free after any kill — re-running the same command is always safe.
