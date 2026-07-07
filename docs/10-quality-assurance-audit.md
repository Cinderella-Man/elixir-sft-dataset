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

---

## 6. Remaining work — step-by-step plan (R1–R11, priority order)

Each step is self-contained: files, approach, acceptance criteria, gotchas.
Steps marked **[decision]** need the user's choice before implementation.

### R1. Commit the current batch + gate evidence **[decision: user must approve commit]**
- `git add` the files listed at the top of §5 + `test/gen_task/cycle_test.exs`.
- Consider committing `results/summary_*.txt` + `results/perfect_failures.txt` (tiny)
  from the next full run so the repo carries proof of corpus state (currently
  `results/` and `logs/` are gitignored — check `.gitignore` before forcing).
- Acceptance: `mix test` green; `elixir scripts/validate.exs --only "001_001*"` green.

### R2. Fix the four known-bad golds (§1.4) — mostly deterministic edits
Work one task family at a time; after EACH family run
`elixir scripts/validate.exs --only "<family>*"` AND `--mutants --only "<family>*"`.

**R2a. `105_001_genserver_based_debouncer` — stale-timer race (REAL bug in gold).**
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

**R2b. `102_001_genserver_based_state_machine_with_persistence` — grader contamination.**
- Minimum fix: delete the comment naming `FakeRepo` (solution.ex:262-264) and rephrase
  to describe the CONTRACT ("repos are expected to return the full struct from
  insert"). The gold must not reference its test double.
- **[decision]** Bigger fix (harness's FakeRepo ignores order_by/limit/select, making
  the "chronological order" requirement untestable): either make FakeRepo honor
  `order_by`/`limit`/`select` on its `all/2`/`one/2`, or migrate the task to the
  SQLite tier-B kit. Recommend the faithful-fake option (self-contained, no infra).
- Same cascade rules as R2a (this is a multifile bundle; children: `grep 102_001`).

**R2c. `623_001_mini_elasticsearch_like_inverted_index` — vacuous tests + stemmer.**
- Two tests (test_harness.exs:124-131, 150-159) have all tf-idf scores 0.0 because
  idf = log(2/2) = 0 with 2 docs both containing the term; they pass only via
  map-order + stable-sort accident under `seed: 0`. Fix: add a third document that
  does NOT contain the term so idf > 0 and the intended ranking is real; assert the
  full ordered id list.
- Prompt/harness contradiction: prompt.md:7 lists the stemmer minimum
  (-ing/-ed/-s/-ly/-tion/-ment) but test_harness.exs:186-187 requires "runner" to
  match "running" (needs "-er" + double-consonant dedup). Align the HARNESS to the
  PROMPT (drop the "runner" expectation) — the prompt is the contract; alternatively
  extend the prompt, but then any trained model must infer more. Recommend harness edit.
- Stemmer inconsistency (`meetings`→`meeting` vs `meeting`→`meet`) is then untested
  either way; optionally normalize (iterate suffix stripping to fixpoint) — only if
  the prompt is updated to say so.
- Cascade as above (children: `grep 623_001`).

**R2d. `wt_131_004_resumable_streaming_json_array_parser_with_error_budget` — spec
contradicts gold.**
- prompt.md:68-69 says `:last_index` is 0 when `resume_from` is past the end; the gold
  harness asserts `== 5` (test_harness.exs:151-156) matching the impl. Fix the PROMPT
  text (the impl+harness agree; the spec sentence is the outlier). The parent
  `131_004_*_01/prompt.md` likely carries the same sentence — fix both, plus any FIM
  children embedding it.

### R3. Stop deriving `wt_`/`tfim_` from vacuous seeds (audit gen-loop 3.4)
- Today `lib/gen_task/cli.ex:194-233` (`warn_if_vacuous_seed`) warns and DERIVES ANYWAY;
  a known-vacuous seed harness becomes the gold completion of a `wt_` task.
- Change: make the cached verdict (`logs/seed_verdicts.jsonl`) a GATE for the
  `:write_test` and `:test_fim` work types — skip minting, record
  `{status: :skipped, reason: "vacuous seed"}` in the ledger so `work_status.exs`
  shows it (rows come from `GenTask.Work` — see docs/09 §12).
- NOTE: the 2026-07-08 `--mutants` sweep proved NO current wt_ gold harness is
  whole-solution-vacuous, so this gate protects FUTURE derivation only — do it, but
  it is no longer the emergency the audit thought.
- Acceptance: unit test in `test/gen_task/` with a fake vacuous verdict; `mix run
  scripts/work_status.exs` shows the skip.

### R4. Blind re-solve screen — the prompt↔harness consistency check **[decision: LLM budget]**
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

### R6. Formatter gate + toolchain pin **[decision: reformat churn]**
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

### R7. Cheap deferred gate upgrades (audit gen-loop 3.6/3.8/3.9, docs/06 §11)
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

### R8. Dedup / leakage stats in `scripts/dataset_stats.exs` (deterministic, no decisions)
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
- Known suspects (union of runs so far): `104_004_usage_recycling_connection_pool_01`,
  `tfim_012_003_inventory_stock_event_sourced_aggregate_10`, `tfim_009_002_*_04`,
  `tfim_031_003_*_03`, `tfim_031_004_*_11`, `tfim_625_001_*_02`.
- Run `elixir scripts/validate.exs --stability 3` a few times over a week;
  aggregate `logs/flaky.jsonl` (`jq -r .task logs/flaky.jsonl | sort | uniq -c`);
  fix repeat offenders by converting wall-clock waits to the injected fake-clock
  pattern (exemplar: `tasks/008_001_*/test_harness.exs` or `wt_010_001`'s Agent clock).
  A tfim flake means the PARENT harness block is timing-sensitive — fix the parent and
  cascade (same rules as R2a).

### R10. Semantic mutants (assertion tightness) — measurement first
- Extend `GenTask.Mutation` with a small operator set applied per public function:
  swap `<`/`<=` and `>`/`>=`, `+1`/`-1` on integer literals, `:ok`↔`:error` in
  returned tuples, boolean literal flip. Reuse the `mutate_fn/4` prewalk plumbing.
- Add `validate.exs --semantic-mutants` REPORT-ONLY (kill-rate per task, no gate):
  the corpus was never held to this bar; measure before deciding thresholds.
- This is the deterministic upgrade path for "raise-mutants prove invocation, not
  assertions" (§1.3) and would double as tfim per-block strength measurement.

### R11. CI + evidence + hygiene
- CI job (GitHub Actions if the repo gets a remote, else a documented local
  pre-push hook): `mix test` + `elixir scripts/validate.exs --only "<changed
  families>"`, full sweep nightly. Needs the R6 toolchain pin.
- Back up `logs/` (552 captured attempt chains are one `rm -rf` from gone) and run
  `mix run scripts/mint_repairs.exs -- --dry-run` (now hang-safe after 5.7) to see the
  mintable repair-pair yield; then mint for real **[decision]**.
- GC `.gen_staging/` (2,660 leftover `*_seedmut` dirs).
- Update stale docs: docs/05 still documents `--fim-only`/`--green-only` flags
  (now `--fim`/`--green`); `prompts.ex:6` references dead `tasks/*.md` meta-prompts.

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
```
