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

## 5. Recommended execution order

1. **Prompt↔harness consistency**: second-blind-solve acceptance gate; blind re-solve for
   variations; harness-assertion lint (`:sys.get_state`, internal sends, `:infinity`
   contract); backfill scan of the 50/36/62 hidden-contract harnesses and re-derive their
   prompts or harnesses. (§1.1, §1.2)
2. **Close vacuous-test paths**: mutation gate for all shapes in `validate.exs` default;
   mutated-reference grading for `wt_`/`tfim_` candidates; stop deriving from vacuous seeds;
   test-count floor; `init/1` exemption scoped to Plug. (§1.3)
3. **Fix the perfect-gate rounding hole + repair test-deletion guard** — small diffs,
   immediate assurance. (§1.5, §1.6)
4. **Triage known-bad golds**: 105 family (fix race, regenerate `_03`), 102_001 (de-contaminate,
   Ecto-faithful fake or Tier-B), 623_001 (fix vacuous tests + stemmer), wt_131_004 (align
   spec with impl); then a stratified review pass to size the remaining tail. (§1.4, §4.4)
5. **Formatter + toolchain pin + per-function AST doc/spec checks + Credo**; one-shot
   corpus reformat. (§3.1, §3.2)
6. **Flake quarantine + timeouts everywhere + silent-skip reporting**. (§2.2, §2.3)
7. **Dedup/leakage stats + family-keyed split + register-diversity metric**. (§4.1, §4.2)
8. **Run mint_repairs (with timeout), add CI, commit gate evidence, back up logs.** (§4.3)
9. Template upgrades (checklist, shared rule block, exemplar rotation) and FIM hardening
   (skeleton AST check, description validation). (§3.4, §1.7)
10. Sandbox/out-of-band result channel — before any untrusted/alternate-model grading. (§2.1)
