# Elixir SFT Dataset

A machine-verified dataset of Elixir programming tasks for **supervised
fine-tuning (SFT)** of code models — plus the evaluator and the generation
pipeline that built it.

**New to SFT?** Supervised fine-tuning teaches a language model by example:
each training example is a *prompt* (what a user asks) paired with a
*completion* (the answer we want the model to learn to give). Fine-tuning on
thousands of such pairs teaches a model to write idiomatic, correct Elixir.
The hard part is that every completion must actually be *good* — a dataset of
subtly buggy solutions teaches a model to write subtle bugs.

This repository's central idea: **every example is verified by execution, and
the tests doing the verifying are themselves verified.** Each task directory
contains a prompt, a reference solution, and a test suite; the solution must
pass its tests perfectly in an isolated Elixir VM, the tests must provably
discriminate (deliberately broken solutions must fail them), and the prompt
must provably contain enough information (an independent model solving from
the prompt alone must succeed). Section [Quality assurance](#quality-assurance-the-gates-and-why-each-exists)
explains every gate.

**Where is the project right now?** Always answered by [`STATUS.md`](STATUS.md)
— whether we are generating new data or catching existing data up to a raised
quality standard.

## The dataset at a glance (2026-07-19)

**12,466 exported training examples (~51M tokens, estimated at ~4 chars/token)
across 10 task shapes and 83 task families — or, counted conservatively,
5,964 examples excluding the test-FIM carvings** (the 6,502 `tfim_` units
each blank one test out of a shared parent suite, so they intentionally share
family text; the advisory `sample_weight` 0.25 in the export reflects that).
Split 11,988 train / 478 val, family-atomic (no family straddles the split).
Zero overlaps against the public Elixir benchmarks (MultiPL-E
humaneval/mbpp-elixir, McEval; 786 benchmark rows, 8/10-gram + exact match —
re-checked 2026-07-19 over all 25,112 corpus texts after the sfim landing).

Every example's completion is **execution-verified at a perfect score**
(compiles, zero warnings, every harness test green, house style clean), and
the harnesses themselves are quality-tested: per-function raise-mutants must
be killed, a semantic-mutant kill floor holds, `@spec`s are Dialyzer-checked,
and every prompt passed (or holds a judged keep for) an independent
blind-solve screen. Export contract + round-trip validator: `docs/16`.

| shape | examples | one example = |
|---|---|---|
| base + variation tasks (`*_01`) | 326 | prompt (a spec) → full module solution |
| multi-file (bundles within `*_01`) | 6 | spec → several files (controller + schema + migration…) |
| code fill-in-the-middle (`*_02+`) | 3,532 | module with one function blanked → that function (2,541 deterministically carved — every uncovered function of every single-module root) |
| write-tests (`wt_*`) | 331 | module + spec → a full test suite |
| test fill-in-the-middle (`tfim_*`) | 6,502 | test suite with one test blanked → that test |
| bug-repair pairs (`bugfix_*`) | 962 | working spec + one-line-bugged module + real failing report → the fix |
| brownfield adaptation (`adapt_*`) | 249 | a related working module + a new spec → the modified module |
| de-documentation (`dedoc_*`) | 326 | doc-stripped module → the fully documented module |
| style repair (`style_*`) | 50 | working-but-style-rejected code + the review → house-style fix |
| multi-turn repair dialogues (`dialog_*`) | 182 | spec → failing attempt → real failure report → … → accepted fix |
| **total** | **12,466** | ~51M tokens |

## Task naming and families

```
001_001_rate_limiter_01
 a   b       c        d
```

- **a** — task (idea) number, 3 digits
- **b** — variation number, 3 digits (`001` = the original task, `002+` =
  variations of the same idea with meaningfully different requirements)
- **c** — task name
- **d** — subtask number, 2 digits (`01` = the full task; `02+` =
  fill-in-the-middle children derived from it)

Derived directories add a **prefix** instead: `wt_001_001_rate_limiter`
(write-tests) and `tfim_001_001_rate_limiter_02` (test-fill-in-the-middle),
and `repair_<parent>_<NN>` for minted bug→fix pairs.

A **family** is one `a_b` pair plus everything derived from it — the `_01`
seed, its FIM children, its `wt_` copy, its `tfim_` children, its repairs.
Children embed the parent's module/harness text **verbatim**, which has two
consequences you must not forget:

1. **Editing any `_01` task cascades.** `ls tasks/ | grep <NNN>_<VVV>` before
   editing, and re-validate the whole family afterwards
   (`--only "*<NNN>_<VVV>*"`). CI enforces that child prompts stay in sync
   with their parents.
2. **Train/validation splits must group by family** — ~92% of completions
   appear verbatim inside a sibling's prompt (by construction). Splitting by
   directory leaks; split by the leading task number.

## Quality assurance: the gates, and why each exists

The philosophy in one sentence: *code that runs green is necessary but nowhere
near sufficient* — tests can be vacuous, prompts can hide requirements,
assertions can be loose, and repairs can quietly delete what they can't fix.
Each gate below exists because we found the corresponding failure mode in
practice (the full campaign is documented in `docs/10`).

| Gate | Failure mode it kills | Where it runs |
|---|---|---|
| **Perfect score, raw invariants** — compiles, **zero warnings**, ≥1 test passed, 0 failed, 0 errored, full style analysis; scored as `tests·0.7 + analysis·0.2 + compilation·0.1` with four hard-fails to 0.0 (no compile, warnings, zero tests ran, any test errored) | a "mostly passing" solution shipping as gold; rounding a 0.995 up to perfect | generation loop + full validation sweep |
| **Mutation gate (raise mutants)** — gut the solution (whole-module, and per public function including GenServer `init/1` for new tasks) and require the tests to FAIL | vacuous test suites: `assert true` passes everything, so "reference passes" alone proves nothing | generation loop at accept time; corpus-wide in CI (`--mutants`, `--fim`) |
| **Semantic mutants** (report) — subtle breaks (`<`↔`<=`, ±1, `:ok`↔`:error`) and measure the kill rate | tests that only prove functions were *called*, not that behavior is *pinned* | manual sweep, ledger `logs/semantic_mutants.jsonl` |
| **Blind-solve screen** — an independent model must solve each seed from `prompt.md` ALONE; failures are triaged (prompt fixed, or documented as a legitimately hard task) | prompts that secretly require reading the tests: hidden option values, undocumented APIs, internal state shapes | in-loop for new variations; ledger `logs/screen_blind.jsonl` (moving fully into the loop — docs/12 §5.2) |
| **Repair guards** — a fix reply may never delete tests, never edit the prompt of a base/variation; byte-identical fixes are not re-graded | the fixer's path of least resistance: delete the failing test, or bend the spec | generation loop |
| **Canonical formatting** — every corpus file is `mix format` output under the pinned toolchain; generation auto-formats before grading | style drift between eras; models learning three different formatting habits | generation loop + CI (`format_corpus.exs --check`) |
| **Embed staleness** — child prompts must byte-match regeneration from current parent files | fixing a parent while children keep showing the old code to the trainee | CI + pre-push (dry run of the resync tool) |
| **Flake ledger** — a test that fails under parallel load but recovers serially still passes, but is *recorded*; repeat offenders get fixed (fake clocks / wider deadlines), never weakened | timing-sensitive harnesses silently gating on machine load | every validation sweep → `logs/flaky.jsonl`; `--stability N` |
| **Vacuous-seed gate** — derivatives (`wt_`/`tfim_`) are never built on a parent whose tests can't kill a mutant | multiplying a weak family 13× | generation loop |
| **Benchmark decontamination** (report) — every prompt AND solution checked for exact + 8-gram overlap against the public Elixir benchmarks (MultiPL-E, McEval, Exercism) | shipping a corpus that overlaps an eval a downstream consumer will score against | manual sweep (`--decontam`); see below |
| **Work registry** — "what remains to generate" is recomputed from disk every run; every step idempotent | half-finished families after an interrupted run | generation loop + `work_status.exs` |

Current standard and what's still being brought in line:
`docs/12-quality-standard-and-steady-state.md`.

## Prerequisites

- **Elixir 1.20.2 / OTP 29** — pinned in `.tool-versions`. Other versions
  compile, but formatter output and warning sets differ, so gate results are
  only reproducible on the pin.
- **PostgreSQL 16+** — only for tasks marked `db: :postgres` (currently one:
  `017_001_search_endpoint_with_filtering_and_sorting`, which needs `ILIKE`).
  Everything else uses SQLite in-BEAM with no external service. Easiest:
  `docker compose up -d db`. **If it is not running, that task grades RED (not
  skipped)** — you can never silently miss coverage.

```bash
mix deps.get
mix compile        # required — the evaluator lives in lib/ and is compiled
docker compose up -d db    # optional, for the one Postgres task
```

## Evaluating tasks

Every task grades in its own BEAM process — a non-compiling solution cannot
affect any other task. The evaluator auto-detects all shapes.

```bash
# one task — by number or directory; prints one JSON verdict
mix run ./scripts/eval_task.exs 8 | jq                  # task 8, variation 1
mix run ./scripts/eval_task.exs tasks/001_001_rate_limiter_02 | jq   # a FIM child
# grade an alternate model's solution file living in the task dir:
mix run ./scripts/eval_task.exs tasks/076_001_trie_01 solution_Qwen3.5-4B-Q6_K_gguf.ex | jq

# the whole corpus (all shapes), one BEAM per task
elixir ./scripts/run_all.exs --parallel 6
#   → results/<task>.json, results/report_<ts>.json, results/summary_<ts>.txt

# THE quality gate — perfect-score on raw invariants; every eval under a
# wall-clock KILL (EVAL_TIMEOUT_S, default 240s); flakes recovered serially
# still pass but are appended to logs/flaky.jsonl
elixir ./scripts/validate.exs                    # perfect-score, whole corpus
elixir ./scripts/validate.exs --green            # lighter: compiles + tests pass
elixir ./scripts/validate.exs --mutants          # vacuous-harness detector
elixir ./scripts/validate.exs --fim              # FIM mutants vs parent harness
elixir ./scripts/validate.exs --semantic-mutants # assertion-tightness report
elixir ./scripts/validate.exs --decontam         # benchmark-overlap report (see below)
elixir ./scripts/validate.exs --stability 3      # flake recovery needs 3 serial passes
elixir ./scripts/validate.exs --only "001_001*"  # scope any mode by task name

# canonical-format gate
elixir ./scripts/format_corpus.exs --check       # exit 1 on any deviation
elixir ./scripts/format_corpus.exs --apply       # rewrite deviating files

# dataset statistics for SFT planning — counts, token volume, length
# distributions, context-window fit, duplication & leakage report
mix run scripts/dataset_stats.exs                # pretty; --json for machines

# what still needs generating (recomputed from disk; always safe to run)
mix run scripts/work_status.exs                  # work-type × corpus matrix
mix run scripts/work_status.exs --counts         # one compact line

# the evaluator's own unit tests
mix test
```

## Benchmark decontamination

Elixir appears in public code benchmarks, so the first question any downstream
consumer asks is whether this corpus overlaps them. It does not.

**What is checked.** Every corpus `prompt.md` **and** every `solution.ex`
(7,716 texts) is checked against the Elixir subsets of the public benchmarks,
using the Tülu-3 recipe: exact normalized full-text match (lowercase + collapse
whitespace) **plus** word-level 8-gram token overlap. A corpus text is flagged
if it exactly matches a benchmark prompt/solution, or shares a word-level 8-gram
Jaccard ≥ 0.5 **or** ≥ 20 identical consecutive-token 8-grams with any single
benchmark row (two signals so a long verbatim span in an otherwise-different
text still trips even though its Jaccard is diluted). The check is **report-only
— it never blocks**; promoting it to a gate is a later human decision.

**Snapshots checked** (fetched 2026-07-10, 786 rows total):

| Benchmark | Elixir subset | Rows |
|---|---|---|
| MultiPL-E (`nuprl/MultiPL-E`) | `humaneval-elixir` | 161 |
| MultiPL-E (`nuprl/MultiPL-E`) | `mbpp-elixir` | 397 |
| McEval (`Multilingual-Multimodal-NLP/McEval`) | `generation/Elixir.jsonl` | 50 |
| Exercism (`github.com/exercism/elixir`) | practice + concept exercises | 178 |

MultiPL-E is a code-*completion* benchmark with no reference solutions, so those
558 rows contribute prompt text only; McEval and Exercism contribute both.

**Result (2026-07-10): 0 exact matches, 0 near-misses across all 7,716 texts.**
The corpus is clean by a wide margin — the single highest 8-gram Jaccard anywhere
is **0.038** (threshold 0.5) and the most identical 8-grams any text shares with
any benchmark row is **2** (threshold 20), both trivial shared Elixir phrasing.
Classic-exercise *ideas* (rate limiter, LRU, bloom filter, trie…) do overlap
these tracks at the idea level — that is expected and legitimate; the check
targets copied *text*, which is what actually contaminates an eval.

```bash
# 1) build/refresh the fixture (public data, no auth; --force to re-download)
mix run scripts/fetch_benchmarks.exs
#    → test/fixtures/benchmarks/benchmarks.jsonl (machine-generated)

# 2) run the check over the whole corpus (report-only, exit 0)
elixir ./scripts/validate.exs --decontam          # → results/decontam_report.txt
elixir ./scripts/validate.exs --decontam --self-test  # + planted positive control
```

The check fails loudly (exit 1) only if the fixture is missing or empty — a
silent no-op decontamination check is worse than none.

## The generation loop

One non-agentic command walks the idea catalog (`tasks/tasks.md`) and, per
idea, authors the base task, 3 variations, and all derived shapes — grading
every candidate, repairing failures, and enforcing every accept-time gate from
the table above. Design: `docs/04`; code: `lib/gen_task/`.

**Safety properties:** it only *adds* (new task dirs, insert-only catalog
appends) and never edits existing tasks; a task already on disk is skipped, so
any interrupted run resumes by re-running the same command. The generation
model is **hardcoded to Opus** inside `scripts/generate.exs` — no environment
variable can change it.

Prerequisites: the `claude` CLI installed and logged in (calls are
subscription-backed via `claude -p`); `ANTHROPIC_API_KEY` must be **unset** so
the CLI uses the subscription login.

```bash
# one base idea end-to-end — the recommended smoke test
mix run scripts/generate.exs 80

# dry run: generate + grade + repair but write NOTHING
GEN_DRY_RUN=1 mix run scripts/generate.exs 80

# the real thing — ALWAYS through the detacher, so the run survives the
# launching session. Running out of tokens is NORMAL: the transport retries
# every 15 minutes indefinitely until the usage window resets.
scripts/run_detached.sh logs/loop_console.log mix run scripts/generate.exs
```

Watching a run:

```bash
tail -f logs/loop_console.log      # one line per task: ACCEPTED (17 passed, mutant killed, 2 attempt(s))
tail -f logs/runs.jsonl            # structured ledger, one JSON line per task
ls logs/errors/                    # tasks that failed their accept gate
elixir ./scripts/validate.exs      # after a run: the perfect-score gate
```

Every graded attempt is captured to `logs/attempts/` — after a run, verified
bug→fix training pairs can be minted from them deterministically:

```bash
mix run scripts/mint_repairs.exs --dry-run    # see what's mintable
mix run scripts/mint_repairs.exs              # mint tasks/repair_* dirs
```

### Common knobs (env vars)

| Env | Default | Effect |
|---|---|---|
| `GEN_DRY_RUN=1` | off | never write to `tasks/` or the catalog |
| `GEN_LIMIT=N` | ∞ | at most N items per work list |
| `GEN_FROM=a` / `GEN_TO=b` | — | restrict to idea numbers in `[a, b]` |
| `GEN_MAX_RETRIES=N` | 3 | repair iterations before a task goes to `logs/errors/` |
| `GEN_RETRY_FAILED=1` | off | re-attempt tasks sitting in `logs/errors/` |
| `GEN_TFIM_MAX_PER_TASK=N` | 10 | tfim children carved per seed (deterministic) |
| `GEN_SKIP_VARIATIONS=1` / `GEN_SKIP_FIM=1` | off | run only part of the per-idea chain |
| ~~`GEN_MODEL`~~ | — | **ignored** — the model is hardcoded to Opus in `scripts/generate.exs` |

(The gate-skip flags `GEN_SKIP_QUALITY_GATE` / `GEN_SKIP_PER_FN_MUTATION`
exist for debugging; production runs never set them. Catch-up-era scoping
flags are being removed — see docs/12 §7.)

## Derived shapes are minted, not generated

From every accepted seed, the multipliers are **deterministic — zero LLM
cost** (design: `docs/06`): the `wt_` dir reuses the module as prompt context
and the harness as the gold completion; `tfim_` children blank one test at a
time; `repair_` pairs come from the loop's own captured failed attempts,
double-verified (fix green AND broken red against the same harness) before
minting.

## Hooks, CI, and the nightly sweep

```bash
git config core.hooksPath .githooks    # install the pre-push gate
```

- **pre-push**: `mix test` + perfect/mutant/format/embed-staleness gates
  scoped to the families you touched.
- **CI** (`.github/workflows/validate.yml`): per push — compile with warnings
  as errors, `mix test`, mutation gate, format gate, embed-staleness gate
  (with a Postgres service so the db task grades); weekly + manual dispatch —
  the full perfect-score and FIM sweeps.
- **nightly flake sweep** (`scripts/nightly_sweep.sh`, cron it on a machine
  that's always on): compiles, runs `validate.exs --stability 3`, aggregates
  `logs/flaky.jsonl` per task and per test. A task reaching ≥2 ledger
  occurrences gets fixed (fake clock or wider deadline — assertions are never
  weakened). Pure CPU, no LLM calls.

## Contributing a task by hand

The generation loop does all of this automatically; manual contribution is
still welcome:

1. Pick an unbuilt idea from `tasks/tasks.md`.
2. Create `tasks/<NNN>_001_<snake_case_name>_01/` with `prompt.md`,
   `solution.ex`, `test_harness.exs` (use
   `tasks/001_001_rate_limiter_01/` as the reference for structure; the
   harness module must be named `<Something>Test`, no `ExUnit.start()`).
3. Verify — the same gates the loop enforces:

```bash
mix run ./scripts/eval_task.exs <task_number> 1 | jq          # grade it
elixir ./scripts/validate.exs --only "<family>*"              # perfect-score
elixir ./scripts/validate.exs --mutants --only "<family>*"    # tests kill a mutant
elixir ./scripts/format_corpus.exs --check --only "<family>*" # canonical format
```

Remember the cascade rule: if you edit an existing `_01`, re-validate the
whole family (`--only "*<NNN>_<VVV>*"`), and expect seed-prompt edits to be
re-screened for blind solvability.

(The step-by-step manual LLM workflows and their meta-prompts under
`tasks/*.md` predate the loop and are kept for historical reference only.)

## Documentation map

| Doc | What's in it |
|---|---|
| [`STATUS.md`](STATUS.md) | **where the project is right now** — always current |
| `docs/01`–`03` | multi-file/FIM design + the evaluator as built |
| `docs/04` | the generation loop: design + env knobs |
| `docs/05`, `docs/08`, `docs/09` | loop audits and hardening history |
| `docs/06` | derived-shape minting (wt_/tfim_/repair_) design |
| `docs/07` | dataset-level audit + growth roadmap |
| `docs/10` | the 2026-07 QA campaign log (read §7 orientation first) |
| `docs/11` | the catch-up plan (phases) + **glossary of project terms** |
| `docs/12` | the quality standard, remaining work, steady-state transition |

## Glossary (the short version — full one in docs/11)

- **seed** — an accepted `_01` task (base or variation) that derivatives are
  built from.
- **family** — a seed plus all its derived dirs; the unit of editing,
  validation, and train/val splitting.
- **harness** — the `test_harness.exs` that grades a solution.
- **mutant** — a deliberately broken solution; tests that don't fail it are
  **vacuous**.
- **blind solve / screen** — solving a task from its prompt alone, to prove
  the prompt is complete.
- **embed** — the copy of parent code/tests inside a child's prompt; kept in
  sync by the staleness gate.
- **ledger** — an append-only JSONL file under `logs/` recording verdicts so
  work never repeats and evidence never disappears.
