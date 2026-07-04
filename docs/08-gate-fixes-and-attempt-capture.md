# 08 — Gate Fixes & Attempt Capture

> **Date:** 2026-07-03
> **Status:** IMPLEMENTED + VERIFIED (unit suite green, all five task shapes
> re-graded unchanged, both bugs re-demonstrated fixed, capture exercised
> end-to-end through the real cycle).
> **Scope:** items **#1 (protect the gates)** and **#2 (attempt capture)** of the
> roadmap in `docs/07-dataset-audit-and-growth-roadmap.md` §9 — and only those.
> Everything else found during implementation is recorded here (§5) and, where it
> is future work, stays in docs/07.

This document describes, in full detail: what was broken, why it mattered, what
the changes do, every file touched, every behavior that changed, everything found
along the way, and how each piece was verified.

---

## 0. Files changed

| File | Change |
|---|---|
| `lib/eval_task/runner.ex` | fixed `seed: 0` for ExUnit; subtract `skipped` from `tests_passed`; new `tests_skipped` field in the eval JSON (incl. `no_tests/0`) |
| `lib/gen_task/evaluator.ex` | `green?/1` now requires `tests_passed > 0`; new `killed_by_tests?/1`; the fallback repair report now names `tests_passed`/`tests_skipped`/`tests_excluded` and says what to fix |
| `lib/gen_task/mutation.ex` | new private `fate/1` (killed / survived / **inconclusive**); all four gate sites rewritten to demand positive evidence in both directions |
| `scripts/validate.exs` | `reference_green` aligned with the new `green?` bar (adds `tests_passed > 0` **and** the previously missing `tests_errors == 0`); FIM mutation check no longer counts a non-compiling mutant as exercised (new `C` failure class) |
| `lib/gen_task/cycle.ex` | `Cycle.run/3` records every graded attempt via `CycleLog.record_attempt/7` (and resets the id's capture dir at cycle start); `repair/4` now receives the precomputed report |
| `lib/gen_task/fim.ex` | the FIM candidate loop (`run_attempts/6`) records its attempts too — all three exit paths (green+killed → accepted, not-green → rejected/rejected_final, gate-survived → rejected_final) |
| `lib/gen_task/cycle_log.ex` | new `record_attempt/7` + `reset_attempts/2`; removed a stale unused `require Logger` (was the repo's only compile warning — `mix compile --warnings-as-errors` is now clean) |
| `test/gen_task/evaluator_test.exs` | new `green?` case (all-skipped) + a `killed_by_tests?/1` describe block |
| `test/gen_task/cycle_log_test.exs` | **new** — attempt-capture round-trip, chain layout, reset semantics |
| `docs/prototypes/proto_attempt_capture.exs` | **new** — end-to-end capture demo through the real cycle (see §4.4) |
| `tasks/020_00{1..4}_*/test_harness.exs`, `tasks/wt_020_*/test_harness.exs`, `tasks/tfim_020_*/prompt.md` (20 files) | cross-BEAM tmp-file collision fix surfaced by the seed change — `:rand`-derived `/tmp` names → OS-pid-qualified (§2.5) |

---

## 1. Fix A — the vacuous-green hole (docs/05 #19, and worse)

### 1.1 What was broken

Two independent bugs compounded into one hole:

**Bug A1 — skipped tests counted as *passed*** (`lib/eval_task/runner.ex`).
`ExUnit.run/0` returns four counters: `total`, `failures`, `excluded`, and
`skipped` (`@tag :skip` when `:skip` is in the exclusion list still surfaces via
`skipped`, not `excluded`). The runner destructured only the first three and
computed:

```elixir
tests_passed: max(total - failures - excluded, 0)
```

so every skipped test landed in `tests_passed`. Demonstrated live
(`docs/prototypes/proto_vacuous_green.exs`): a harness with **two `@tag :skip`
tests whose assertions are FALSE** graded

```
before: total=2 passed=2 failed=0 errors=0  overall=1.0   green? = true
```

A perfect score, from tests that never executed and would fail if they did.

**Bug A2 — `green?/1` demanded no positive evidence**
(`lib/gen_task/evaluator.ex`). The accept-gate predicate was:

```elixir
compiled == true and tests_total > 0 and tests_failed == 0 and tests_errors == 0
```

`tests_total > 0` is satisfiable by a harness whose tests are all excluded or
skipped — nothing required that *any test actually ran and passed*. Even with A1
fixed, `passed=0, failed=0, total=2` would still have been "green".

**Why it mattered:** `green?` is the first of the three accept gates in the
generation loop (`GenTask.Cycle.accept?/4`) and the pre-check inside the tfim
isolation gate. A model-authored harness that skipped its own tests — a real
failure mode for LLM-generated ExUnit — could have been **promoted into the
dataset with a perfect score**, and its wt_/tfim derivatives minted from it.

### 1.2 What the fix does

1. `runner.ex` destructures `skipped` and subtracts it:
   `tests_passed = max(total - failures - excluded - skipped, 0)`. The eval JSON
   gains a new field, **`tests_skipped`** (also zeroed in `no_tests/0`), so
   skipped counts are visible downstream instead of laundered into passes.
2. `green?/1` adds `(json["tests_passed"] || 0) > 0` — green now requires at
   least one test to have **run and passed**.

**Both are required.** Fixing only `green?` is defeated by A1 (skipped are
reported as passed, so `tests_passed > 0` still holds); fixing only the runner
leaves `green?` accepting `passed=0` grades. This interaction is exactly what the
verification pass on docs/07 caught (docs/07 §11.2).

### 1.3 Behavior after the fix (demonstrated)

```
after:  total=2 passed=0 failed=0 errors=0 skipped→ not counted  overall=0.3   green? = false
```

(0.3 = analysis 0.2 + compilation 0.1; the tests component is now honestly 0.)

Knock-on improvements that fall out for free:

- **tfim isolation gate**: its sanity pre-check ("the isolated block must be
  green against the real module") now also rejects an isolated block that is
  skipped/excluded rather than treating it as independent-and-green.
- **`validate.exs` reference-green** was aligned to the same bar (§3).
- **The repair report became actionable** for this reject class: the fallback
  branch of `report_from_json` used to print only
  `compiled=true, tests_total=2, tests_failed=0, tests_errors=0` — all zeros, no
  clue what to repair. It now prints `tests_passed`, `tests_skipped`,
  `tests_excluded` and instructs: *"At least one test must RUN and pass — remove
  `@tag :skip` / excluded tags or fix the harness so its tests execute."* This
  matters twice: it is what the repairing model sees, and (per §4) it is also the
  captured mid-conversation turn in future repair-pair training data.

### 1.4 What did NOT change (scope note)

The *score ratio* still counts excluded/skipped tests in `tests_total`
(`tests = passed/total`), so a partially-skipped harness scores below 1.0 while
being non-green — the semantics inconsistency flagged in docs/07 §6.3 remains
open, deliberately: changing the scoring rubric re-scores the whole corpus and is
a separate decision.

---

## 2. Fix B — nondeterministic grading (no ExUnit seed)

### 2.1 What was broken

`run_harness/1` started ExUnit with
`ExUnit.start(autorun: false, formatters: [EvalTask.FailureCollector])` — no
`seed:`. Nothing else in `lib/eval_task/`, `scripts/eval_task.exs`,
`run_all.exs`, or `validate.exs` set one. Consequences:

- **Test order within a module was random per run.** A harness with hidden
  order-dependence could pass its accept-grade once and fail forever after in
  `validate.exs` — the classic "flaky reference" that then blocks the quality
  gate for unrelated work.
- **StreamData property tests generated from a random seed per run** (StreamData
  derives generation from the ExUnit seed). A property that happens to pass on
  the accept run could fail on any later run with different generated inputs —
  or worse, a *weak* property could pass forever while appearing exercised.

### 2.2 What the fix does

```elixir
# seed: 0 pins test order (and StreamData generation) — without it a flaky
# harness can pass its accept-grade once and fail forever after in validate.exs.
ExUnit.start(autorun: false, seed: 0, formatters: [EvalTask.FailureCollector])
```

`seed: 0` is ExUnit's "do not shuffle" value: tests run in definition order, and
StreamData generation is fixed. Every grade of the same (solution, harness) pair
is now the same grade. This is the property the whole pipeline silently assumed:
accept-gates, mutation gates, `validate.exs`, and future resumable minting all
compare grades across runs.

### 2.3 Verified

Two consecutive evals of the StreamData-based task
(`075_001_property_based_test_generators_01`, 29 tests) produce **byte-identical
JSON modulo the `timestamp` field**.

### 2.4 Trade-offs and residual risk

- Fixed order means order-dependence bugs in *future* harnesses are hidden
  rather than surfaced-by-flake. That is the right trade for a **grader** (its
  job is reproducible verification, not harness fuzzing); if desired, a separate
  audit mode could grade at 2–3 random seeds — noted as optional future work.
- Existing corpus tasks accepted under random seeds may still harbor
  order-dependence that never triggered. A full `elixir scripts/validate.exs`
  sweep (now deterministic) is the recommended follow-up before the next
  generation run — and running it as part of this change immediately caught a
  real one (§2.5).

### 2.5 The seed fix surfaced (and forced the fix of) a real harness-hygiene bug

The first post-fix corpus sweep (`validate.exs --green-only`, which grades tasks
**in parallel, one BEAM each**) failed 7 dirs — all in the 020 file-upload
family — that pass solo. Reproduced deliberately: grading the family
concurrently fails 5/7; solo, 0/7.

**Mechanism.** The 020 harnesses named their shared-`/tmp` scratch files with
`:rand.uniform`:

```elixir
@upload_dir Path.join(System.tmp_dir!(), "file_upload_test_#{:rand.uniform(100_000)}")
tmp_path = Path.join(System.tmp_dir!(), "upload_#{:rand.uniform(100_000)}_#{filename}")
```

ExUnit seeds each test process's `:rand` from the suite seed. Under the old
random seed, every BEAM drew different filenames and the collision never
happened — **randomness was masking a cross-OS-process hygiene bug**. With
`seed: 0`, every BEAM draws the *identical* "random" sequence, two concurrent
evals of the same harness generate the same `/tmp/upload_3518_big_but_ok.csv`,
and one BEAM's cleanup deletes the file under the other (observed:
`File.CopyError … no such file or directory`, plus one 422-vs-201 from a
mid-copy truncation). Note the per-*test* filenames collided while the
compile-time `@upload_dir` did not — module attributes are evaluated during
`Code.compile_file`, outside ExUnit's seeding — which is exactly the fingerprint
of ExUnit-seeded `:rand`.

**Fix.** The repo already documents the correct idiom for this exact problem in
its own evaluator (`runner.ex` `mktemp`: *"System.unique_integer is only unique
within a single BEAM"*): qualify names with the **OS pid**. Applied as a uniform
textual replacement across the whole 020 family:

```elixir
#{:rand.uniform(100_000)}       →  #{System.pid()}_#{System.unique_integer([:positive])}
#{:rand.uniform(1_000_000)}     →  (same)
```

in **20 files**: the 4 parent harnesses (`020_001`–`020_004`), their 4 `wt_`
gold-harness copies, and the 12 `tfim_020_*` `prompt.md` skeletons — the tfim
skeletons matter because test-FIM grading reconstructs the harness **from the
prompt's embedded skeleton**, not from the parent file, so parent and skeletons
must stay textually in sync. (Base `prompt.md`s, solutions, and tfim gold blocks
were checked: clean.)

**Verified:** the 7 previously-failing dirs plus 3 more family members re-graded
**concurrently**: 10/10 green, 0 failures.

**Two general lessons recorded for the pipeline:**
1. Harness tmp-file hygiene is a *reviewable pattern*: anything writing to
   shared `System.tmp_dir!()` must qualify names with `System.pid()` (OS pid) —
   `:rand` and `System.unique_integer` are both insufficient across BEAMs. Worth
   adding to the house-style prompt (`GenTask.Prompts`) and/or as a regex check
   in `analyze_source` so the loop stops authoring the pattern.
2. Derived artifacts (`wt_` harness copies, `tfim_` prompt skeletons) are
   **textual copies** of the parent harness — any hand-fix to a parent must be
   propagated to them, or graded reconstructions silently diverge.

---

## 3. Fix C — mutants "killed for the wrong reason" (docs/05 #18)

### 3.1 What was broken

All four mutation-gate decision points asked only `Evaluator.green?(grade)` and
treated **any non-green** mutant grade as a kill:

- `gate_base_whole/3`, `gate_base_per_fn/4` (base/variation coverage gate)
- `gate_fim/4` (FIM candidate coverage)
- `gate_isolation/4` (tfim target validity)

But "non-green" includes outcomes where **the harness never observed the mutated
behavior at all**: the mutant failing to compile, the harness failing to load
against it, or the 120s eval subprocess timing out. Each of those vacuously
"passed" the coverage gate. (One pre-existing mitigation: a mutation that fails
to *parse* returns the source unchanged — `mutate/1` rescue — grading green and
correctly counting as *survived*. The hole was specifically
parse-OK-but-compile-fail and timeout mutants.)

After Fix A this got subtly **worse** if left alone: an all-skip grade is now
non-green, so a skipped-out harness would have "killed" every mutant.

### 3.2 What the fix does

A mutant's fate now needs **positive evidence in both directions**
(`GenTask.Mutation.fate/1`):

```elixir
cond do
  Evaluator.killed_by_tests?(grade) -> :killed        # ran AND failed
  Evaluator.green?(grade)           -> :survived      # ran AND passed
  true                              -> :inconclusive  # proves nothing
end
```

backed by the new public predicate:

```elixir
# lib/gen_task/evaluator.ex
def killed_by_tests?(%{} = json) do
  json["compiled"] == true and (json["tests_failed"] || 0) > 0
end
# :timeout_or_crash → false
```

Note `tests_errors` does **not** count as a kill: `tests_errors: 1` is the
harness-load-failure / crash path — the tests did not run.

Per-site behavior:

| Site | killed | survived | **inconclusive** (new) |
|---|---|---|---|
| `gate_base_whole` | accept | reject: "tests still pass after every body raised" | reject with explicit reason: "graded inconclusively (mutant compile failure, harness load error, or eval timeout) — coverage cannot be verified" |
| `gate_base_per_fn` | continue to next fn | reject naming the uncovered fn | reject naming the fn + inconclusive reason |
| `gate_fim` | accept candidate | reject: parent doesn't cover target | reject with inconclusive reason |
| `gate_isolation` | target valid (halt on first kill) | keep scanning; "kills no mutant" if none | **keep scanning** — an inconclusive mutant is simply not evidence; other functions may still provide a kill |

**Design decision — inconclusive is strict, not lenient.** For the three accept
gates, inconclusive maps to `{:survived, reason}` with a *distinct, explicit
message*: the cycle treats it as a reject, the repair loop gets a truthful
report, and an exhausted cycle lands in `logs/errors/` where it is visible.
The alternative (skip-and-warn) risks the systematic case — a module whose
mutants *all* fail to compile would pass the gate with zero verified kills,
recreating the vacuity the fix removes. Rarity makes strictness cheap: raise-body
mutants of anything that parses almost always compile (verified empirically —
§3.3). Only `gate_isolation` scans past inconclusive mutants, because there the
question is "does ≥1 mutant provide a kill", not "is every mutant killed".

### 3.3 Verified

- Spot-check of the per-function gate on three references
  (002 circuit breaker, 041 ETS LRU, 100 TOTP — ~15 mutant evals): all
  **`:killed`**, zero inconclusive — the stricter bar does not false-reject
  normal references.
- The green accept path of `proto_attempt_capture.exs` (§4.4) drives
  `gate_base_per_fn` across all 6 public functions of the trie under the new
  logic: accepted.
- Unit tests for `killed_by_tests?/1` (compile-fail, harness-load-error,
  timeout, genuine kill).

### 3.4 `validate.exs` had the same holes independently (found on the way)

`scripts/validate.exs` — the corpus-wide quality gate — duplicated both bugs in
its own predicates and got the matching fixes:

- **`reference_green`** required only
  `compiled && tests_failed == 0 && tests_total > 0`. That misses
  `tests_passed > 0` (the Fix-A hole) **and was missing `tests_errors == 0`
  entirely** — a task whose harness fails to load reports
  `tests_errors: 1, tests_failed: 0` and would have been counted GREEN by the
  validator. Both conditions added; the bar now matches
  `GenTask.Evaluator.green?/1` exactly.
- **`fim_mutation`** deliberately counted a non-compiling mutant as exercised
  (`compiled != true or tests_failed > 0` — the old comment even said "or not
  compile"). It now requires `compiled && tests_failed > 0`, and a non-compiling
  mutant is reported as its own failure class — printed **`C`**, message
  *"mutant did not COMPILE — coverage unverifiable"* — instead of silently
  passing, so genuine anomalies surface for investigation rather than being
  absorbed.

---

## 4. Attempt capture (docs/07 §4.2 — the #2 change)

### 4.1 What was being lost, exactly

Every rejected attempt inside the two repair loops produced three artifacts:

1. the broken candidate files (staged into `.gen_staging/…`),
2. a structured failure diagnosis (`Evaluator.repair_report/1` — compile
   diagnostics or per-test failure messages), and
3. on a later success, the fixed files.

That is a **verified bug → diagnosis → fix triple** — and across attempts, a
natural multi-turn conversation ("write X" → broken reply → "these tests fail:
…" → fixed reply). Before this change every trace of it was destroyed:

- `Evaluator.stage!/2` begins with `File.rm_rf!(dir)` — staging the next attempt
  **physically deletes the previous candidate**;
- the only record was `Logger.debug` lines inside gitignored
  `logs/<task_id>.log`, and `CycleLog.close/2` *deletes* a prior error log when
  a later attempt succeeds — i.e. precisely the interesting (eventually-fixed)
  failures were the ones erased;
- the JSONL ledgers keep scalar counts only.

The generation loop's most expensive byproduct — model-authored, evaluator-
verified failure→fix transitions — was pure exhaust.

### 4.2 What is captured now, and where

Two new functions in `GenTask.CycleLog`, wired into both repair loops:

```
logs/attempts/<id>/
  attempt_00/
    files/            # the EXACT candidate graded on this attempt
      prompt.md
      solution.ex
      test_harness.exs        # (fim candidates: prompt.md + solution.ex only)
    grade.json        # the full evaluator JSON for this attempt
                      #   (:timeout_or_crash → {"timeout_or_crash": true})
    meta.json         # {"id", "attempt", "status", "repair_report", "ts"}
  attempt_01/
    …
```

`meta.json` fields:

| Field | Meaning |
|---|---|
| `id` | the cycle id — a task id (`065_001_saga_coordinator_01`) or a FIM candidate log id |
| `attempt` | 0-based grade attempt within this cycle |
| `status` | `accepted` \| `rejected` (a repair follows) \| `rejected_final` (retries exhausted, or an unfixable gate reject) |
| `repair_report` | the exact human diagnosis handed to the fixer — compile errors, failing tests with messages, quality shortfall, or mutation-gate reason; `null` on `accepted` |
| `ts` | ISO-8601 UTC |

**Capture points:**

- `GenTask.Cycle.run/3` (bases + variations): records on **every** graded
  attempt — `accepted`, `rejected` (before the repair call), and
  `rejected_final` (retries exhausted). Note a *fix-contract violation* (the
  known consume-an-attempt path) shows up naturally as two consecutive attempts
  with identical `files/` — itself a useful signal.
- `GenTask.Fim.run_attempts/6` (FIM candidates, which have their own loop): all
  three exits — not-green (`rejected` / `rejected_final` with the test-failure
  report), green-but-gate-survived (`rejected_final` with the mutation-gate
  reason — unfixable, since the parent harness may not be edited), and
  green+killed (`accepted`).
- **wtest / tfim mint nothing here** — they are deterministic (no attempts, no
  repairs, nothing to capture).

**Reset semantics:** `reset_attempts/2` runs at cycle start, so
`logs/attempts/<id>/` always holds exactly the *latest* cycle for that id — a
retried task (e.g. `GEN_RETRY_FAILED=1`) replaces its stale history instead of
interleaving two runs. (Trade-off: history-across-runs is not kept; the pairs
worth minting are within-cycle, and keeping cross-run mixtures would corrupt the
attempt chain.)

**Operational properties:** always on (including dry-run — capture is log
exhaust, and dry-run traffic is equally valid training data); `logs/` is already
gitignored so nothing lands in the repo; cost is a few KB per attempt (the three
text files + two small JSONs); `record_attempt` is plain `File.write!` — no
handler, no fsync-per-line ledger needed since each attempt is its own directory.

**Small API change on the way:** `Cycle.repair/4` now takes the precomputed
`report` string instead of the raw reject `reason` (the caller needs the report
for `meta.json` anyway); behavior is byte-identical.

### 4.3 How this becomes training data (the consumer contract)

A future deterministic `scripts/mint_repairs.exs` (docs/07 §4.2, *not* part of
this change) walks `logs/attempts/*/`:

- **single-turn repair pair:** for a `rejected` attempt N with an `accepted`
  attempt M>N in the same dir: prompt = original `prompt.md` + attempt-N files +
  attempt-N `repair_report`; completion = attempt-M files. Verification is free —
  the accepted files already graded green, and the broken files' grade is on
  disk.
- **multi-turn conversation:** the full chain `attempt_00 … attempt_MM`
  alternating candidate/report, ending at the accepted files — `repair_report`
  *is* the user's mid-conversation turn (which is why making it actionable for
  the all-skip class in §1.3 matters).
- `rejected_final` chains (no accepted end state) are negative material:
  hard-task mining, DPO rejected responses, or simply diagnostics.

### 4.4 Verified

- **Unit** (`test/gen_task/cycle_log_test.exs`): files/grade/meta round-trip;
  rejected→accepted chain lays out `attempt_00` + `attempt_01` with the right
  statuses and grade serialization (incl. `:timeout_or_crash`); `reset_attempts`
  clears only the targeted id.
- **End-to-end** (`docs/prototypes/proto_attempt_capture.exs`, run against the
  compiled repo): a green cycle on the real trie task flows through grade +
  quality gate + per-fn mutation gate and captures
  `attempt_00: status=accepted, tests=20/20`; a raise-mutant of `insert/2`
  captures `attempt_00: status=rejected_final, tests=3/20 failed=17` with the
  full repair report (the 17 failing tests, named, with messages); re-running the
  same id leaves exactly one attempt dir (reset semantics).

---

## 5. Everything else found on the way

1. **`validate.exs` was missing `tests_errors == 0` in reference-green** — a
   harness-load failure would validate as green. Fixed (§3.4). This was *not* in
   the docs/07 audit; it surfaced while aligning predicates.
2. **The fallback repair report was content-free for the new reject class**
   (all zeros, no mention of skipped) — made actionable (§1.3). This text is now
   also future training data via capture (§4.3).
3. **`cycle_log.ex` carried the repo's only compile warning** (unused
   `require Logger` — `Logger.configure/1` and `Logger.Formatter.new/1` are
   plain functions, no `require` needed). Removed;
   `mix compile --warnings-as-errors` now passes, which is worth keeping as a CI
   invariant given the loop's own zero-warning quality gate.
4. **New JSON field `tests_skipped`** in every eval result. Additive — nothing
   consumed the old shape's absence — but downstream JSON consumers
   (`run_all.exs` report readers, `dataset_stats.exs`) can now distinguish
   skip-laden harnesses. The top-level `"skipped"` key that `validate.exs`
   checks for db-manifest skips is a different, pre-existing field; no collision.
5. **`Cycle.reason_for/1` wording**: an all-skip reject prints as "vacuous
   harness (mutant survived)" on the progress line — slightly off (it never
   reached the mutation gate) but harmless; the captured `repair_report` and
   grade JSON carry the truth. Left as-is to keep the change surface minimal.
6. **Scoring still counts skipped/excluded in the tests denominator**
   (docs/07 §6.3) — explicitly out of scope here; re-scoring the corpus is its
   own decision.
7. **The 020 family's cross-BEAM tmp-file collision** — surfaced by the seed
   fix, root-caused, and fixed across 20 files (full story in §2.5). Two
   pipeline-level lessons recorded there: OS-pid-qualified tmp naming belongs in
   the house style / static checks, and `wt_`/`tfim_` derivatives are textual
   copies of the parent harness that must be kept in sync on any hand-fix.
8. **`validate.exs --fim-only`'s summary prints "reference-green: all pass"
   even when that half was skipped** (an empty failure list is
   indistinguishable from "not run") — cosmetic, noted, unchanged.
9. **A flaky-reference audit is now possible and worthwhile**: with `seed: 0`,
   two `validate.exs` sweeps that disagree indicate genuine nondeterminism (time,
   process races) rather than seed noise. The first sweep was executed as part of
   this change and is what caught §2.5.

## 6. Verification summary

| Check | Result |
|---|---|
| `mix compile --warnings-as-errors` | clean (warning removed) |
| `mix test` (133 tests incl. new `killed_by_tests?`, green? all-skip, cycle_log capture) | **133 passed** |
| `proto_vacuous_green.exs` re-run | bug gone: `passed=0, overall=0.3, green?=false` (was `passed=2, overall=1.0, green?=true`) |
| Re-grade across all five shapes (002 single, 016 multifile, 001_001…_02 fim, wt_002, tfim_002, 075 StreamData) | unchanged: 1.0 / 1.0 / 0.99 / 1.0 / 1.0 / 1.0, `tests_skipped=0` everywhere |
| Determinism: 075 (StreamData) evaluated twice | byte-identical JSON modulo `timestamp` |
| Strict mutation gate on 002 / 041 / 100 (per-fn, ~15 mutant evals) | all `:killed`, zero inconclusive |
| Attempt capture end-to-end (green accept + mutant reject + reset) | all as specified (§4.4) |
| `validate.exs --fim-only` (all 409 FIM dirs) under the strict mutant predicate | **ALL PASS** — zero `C` (non-compiling mutant), zero `U` (under-tested): every historical FIM kill was genuine |
| `validate.exs --green-only` (full corpus, parallel, fixed seed) under the strict bar | first sweep FAILED 7 dirs → root-caused as the §2.5 cross-BEAM tmp collision (a real pre-existing hygiene bug the old randomness masked) → fixed → **re-sweep ALL PASS** |

> **Why the FIM sweep matters:** the strict predicate re-classifies any
> historical "kill" that was actually a mutant compile failure as
> `C — coverage unverifiable`. The clean sweep confirms the docs/01-era finding
> (`docs/prototypes/mut_fim.exs`: 54/54 genuine on the then-corpus) now holds for
> the full 409 — the fix closes the hole without invalidating existing data.
