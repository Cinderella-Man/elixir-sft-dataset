# CONTEXT.md — Elixir SFT Dataset

> Deep reference for this repository. Written to let an engineer (or an agent) who
> has never opened the project understand *everything*: what it is, how it is laid
> out, how tasks are authored and scored, and what each of the ~170 tasks actually
> teaches — down to the algorithm, interface, and edge cases per task family.

> **⚠️ Post-implementation update (2026-07-01).** Two things below are now out of date:
> (1) **`tasks_multifile/` no longer exists** — its 11 tasks were merged into `tasks/` under the
> standard `a_b_c_d` naming (e.g. `016_001_paginated_list_endpoint_01`), and all are now solved.
> (2) The **evaluator was rebuilt** into `lib/eval_task/` (compiled, tested) and now auto-tests all
> three task shapes — single-file, multi-file, and **fill-in-the-middle** (previously untested).
> The **analysis score was also fixed** (it used to be a constant 1.0). See `README.md` and
> `docs/01`–`03` (esp. `docs/03` §12–13) for the current state.

---

## 1. What this project is

This repo is **not an application** — it is a **hand-built dataset + evaluation harness for
generating Elixir SFT (supervised fine-tuning) training data**. It is a benchmark suite of
self-contained Elixir coding problems. Each problem bundles:

- a natural-language **prompt** (the request you'd give an LLM),
- a reference **solution**, and
- an ExUnit **test harness** that verifies any candidate solution.

A tiny Mix project wraps the collection so that solutions can be compiled and their harnesses
run in isolated BEAM processes and scored (compilation + tests + static-analysis quality). The
`README.md` frames the whole thing as *"A framework for evaluating AI-generated Elixir code
against verified test harnesses. Each solution runs in its own BEAM process — a non-compiling
solution cannot affect any other task's evaluation."*

The dataset is deliberately **OTP/stdlib-heavy**: the large majority of tasks forbid external
dependencies and drill deep OTP idioms (GenServer, ETS, `Process.monitor`, `Task`,
`Process.send_after`, injected clocks for determinism). A minority of tasks use Phoenix/Ecto/Plug.

### At a glance

| Fact | Value |
|---|---|
| Purpose | Generate & evaluate Elixir SFT training tasks |
| Elixir / OTP | `~> 1.17` / OTP 27+ (README); Postgres 16+ only for DB-tagged tasks |
| Task directories in `tasks/` | **165** (each has `prompt.md` + `solution.ex`; **111** also have `test_harness.exs`) |
| Task directories in `tasks_multifile/` | **11** (7 are unsolved: prompt + harness, no solution) |
| Distinct base task ideas realized | ~57 (of a ~1000-idea backlog ≈ 6%) |
| Reference-solution LOC | ~26.8k lines across `solution*.ex` |
| Test-harness LOC | ~34.1k lines (harnesses are *larger* than solutions — verification is rigorous) |
| Prompt LOC | ~15.4k lines |
| Alternate-model solutions | **1** (`tasks/076_001_trie_01/solution_Qwen3.5-4B-Q6_K_gguf.ex`) |
| Git history | 63 commits, single author (Kamil Skowron), all hand-authored |
| External deps actually used in solutions | Jason (52×), Ecto (43×), StreamData (30×), Plug (20×), Decimal (15×), Phoenix (8×), NimbleCSV (5×); everything else pure OTP |

---

## 2. Repository layout

```
elixir-sft-dataset/
├── README.md              # Purpose, setup, naming convention, contribution workflow
├── mix.exs                # Mix project `:elixir_benchmark` — deps for every task type
├── mix.lock               # Locked deps (Phoenix 1.8.5, LiveView 1.1.28, Nx 0.11, Explorer 0.11, …)
├── .formatter.exs         # Formats config/lib/test AND tasks/**/*.exs
├── .gitignore             # ignores _build, deps, *.db, results/, tmp
├── config/
│   ├── config.exs         # logger level :warning; imports env config
│   ├── dev.exs            # logger :info
│   └── test.exs           # logger :error
├── lib/elixir_benchmark/
│   └── application.ex     # Empty supervisor (children = []). App does nothing at runtime.
├── lib/eval_task/         # ★ The evaluator library (Bundle/Discovery/Runner/Fim/…) that
│                          #   eval_task.exs drives; grades single-file, multi-file & FIM shapes
├── lib/gen_task/          # ★ The automated task-generation loop (docs/04). Non-agentic driver
│                          #   that authors base+variations+FIM via `claude -p`, grades, repairs,
│                          #   mutation-gates, and promotes. Modules: cli, config, catalog, opus,
│                          #   reply, cycle, evaluator, mutation, base, variations, fim, cycle_log
├── test/
│   ├── test_helper.exs    # ExUnit.start(exclude: [:skip, :database]); conditionally starts a Repo
│   └── support/
│       └── call_tracker.ex# ElixirBenchmark.CallTracker — Agent that records fn calls, for tests
├── docs/                  # Design docs: 01–03 multi-file support, 04 the generation loop, 05 loop audit
├── logs/                  # Generation-loop output: <task_id>.log per cycle, errors/ for failures,
│                          #   runs.jsonl / usage.jsonl / waits.jsonl ledgers (git-ignored)
├── scripts/
│   ├── eval_task.exs      # ★ Core evaluator: compile one solution + run its harness → JSON score
│   ├── run_all.exs        # Batch-run eval_task across all tasks → results/*.json + summary
│   ├── generate.exs       # ★ Entry point for the generation loop → GenTask.CLI.main (docs/04)
│   ├── validate.exs       # Quality gate: every reference green + every FIM target mutation-killed
│   └── validate_harnesses.sh # Sanity-compiles every harness (catches harness syntax bugs)
├── tasks/                 # ★ ~312 single-file/FIM task dirs (a_b_c_d naming) + the meta files below
│   ├── tasks.md           # Master catalog of PURE (stdlib/OTP) task ideas (~558 numbered)
│   ├── tasks_external.md   # Master catalog of EXTERNAL-dep task ideas (~442 numbered)
│   ├── single_shot_prompt.md      # Meta-prompt: turn an idea into a task prompt + harness
│   ├── variation_prompt.md        # Meta-prompt: spin one task into 3 problem variations
│   └── fill_in_the_middle_prompt.md # Meta-prompt: carve FIM subtasks out of a solution
└── tasks_multifile/       # 11 whole-app Phoenix/Ecto/Plug/OTP tasks (flat dirs, no a_b_c_d)
```

`lib/` and `config/` exist only to make `mix compile` / `mix run` work so `eval_task.exs` can load
the deps; the `ElixirBenchmark.Application` supervisor starts **no children**. There is no running
service. (Note: `test/test_helper.exs` references `ElixirBenchmark.Repo`, but **no such module is
defined anywhere** — the `:database` path is aspirational and never exercised, since `ExUnit.start`
excludes `:database` and no harness carries that tag.)

---

## 3. The `a_b_c_d` naming convention (critical)

Every directory under `tasks/` is named:

```
001_001_rate_limiter_01
 │   │       │        │
 a   b       c        d

a = task number        (the base idea, e.g. "1. Rate Limiter")
b = variation number   (01 = original problem; 02+ = a DIFFERENT problem that is a
                        meaningful spin on the base — e.g. sliding-window vs fixed-window
                        vs hierarchical vs penalty-escalation rate limiters)
c = task name          (lowercased, underscores only)
d = subtask number     (01 = full "single-shot" solution WITH a test_harness.exs;
                        02+ = "fill-in-the-middle" (FIM) subtask: prompt.md embeds the whole
                        module with ONE function's body replaced by "# TODO", and solution.ex
                        contains ONLY that one function. FIM dirs have NO test_harness.exs.)
```

Consequences you must internalize:

- **`_01` dirs are the real, complete, testable tasks.** There are 111 of them (matching the 111
  `test_harness.exs` files). The 54 non-`_01` dirs are FIM subtasks with only `prompt.md` +
  `solution.ex`.
- **Different `b` = different problem** (e.g. `001_001_rate_limiter`, `001_002_fixed_window_counter`,
  `001_003_hierarchical_limiter`, `001_004_penalty_escalation` are four separate rate-limiter
  problems, all sharing task number 1).
- The `eval_task.exs` resolver takes `<task> <variation>` (the `a` and `b` numbers) and globs
  `tasks/{a padded to 3}_{b padded to 3}_*_01/` — i.e. it always evaluates the `_01` subtask.
- `tasks_multifile/` breaks this scheme: those dirs are flat (`016_paginated_list_endpoint`), and
  the reference `solution.ex` there bundles *multiple* modules inline via `<file path="...">…</file>`
  blocks.

---

## 4. The three file types

**`prompt.md`** — a conversational coding request ("Write me an Elixir GenServer module called
`RateLimiter` that…"). It specifies the exact public API, the algorithm, required options, edge-case
behavior, and usually ends with a hard constraint like *"Use only OTP standard library, no external
dependencies. Give me the complete module in a single file."* FIM prompts instead embed the entire
module (with the target function blanked to `# TODO`) and ask for just that function.

**`solution.ex`** — the reference implementation. Canonical solutions are heavily documented
(`@moduledoc` with ASCII tables/examples, `@doc` + `@spec` on public functions) and visibly written
to the scoring rubric (see §6). For a family's `_01` it is the whole module; for a FIM subtask it is
just the one target function. A directory may also hold `solution_<MODEL>.ex` (an alternate model's
attempt scored against the same harness — only one such file exists today, a broken Qwen3.5-4B trie).

**`test_harness.exs`** — an ExUnit file (its own `defmodule …Test do use ExUnit.Case`) that verifies
any solution against the spec. These are the ground truth. Recurring harness idioms:
- `use ExUnit.Case, async: false` for shared/named-process/ETS state (76 files) vs `async: true` for
  pure modules (45 files);
- an inline fake **`Clock`** built as an `Agent` (`now/0`, `advance/1`, `set/1`) injected via a
  `:clock` option, so time-dependent logic is fully deterministic with **no real `Process.sleep`**;
- `start_supervised!({Mod, opts})` for auto-teardown, and unique names via
  `:"name_#{System.unique_integer([:positive])}"` to avoid collisions;
- white-box assertions through `:sys.get_state/1` (to check internal maps shrank after cleanup) and
  manual `send(pid, :cleanup)` + a follow-up sync call to force deterministic sweeps;
- side-effect tracking via counting `Agent`s or the process dictionary.

---

## 5. The evaluation harness (`scripts/eval_task.exs`)

The heart of the framework. `mix run ./scripts/eval_task.exs <task> [<variation>] [<solution_file>]`
compiles one solution and runs one harness **in the current BEAM**, emitting a single JSON object.

**Argument forms** (`parse_args/1`):
- `eval_task.exs 8` → task 8, variation 001, `solution.ex`
- `eval_task.exs 8 2` → task 8, variation 002
- `eval_task.exs 8 2 solution_Qwen….ex` → evaluate an alternate solution file
- (commented-out) direct `<solution> <harness> [support]` forms

`resolve_task_args/3` pads the numbers to 3 digits and globs `tasks/{a}_{b}_*_01/`, requiring exactly
one match (else it throws "No task directory found" / "Multiple matches").

**Pipeline** (`EvalTask.main/1`):
1. `compile_solution/1` — `Code.with_diagnostics` + `Code.compile_file`, capturing warnings vs errors
   separately. A compile failure short-circuits tests.
2. `analyze_source/1` — a **regex** static-analysis pass (no AST): detects `@moduledoc`, `@spec`,
   `@doc`, line count, `max_line_length`, `lines_over_98`, public/private fn counts,
   `TODO|FIXME|HACK|XXX`, pipe-chain count, and a crude `sql_injection_risk` interpolation check.
3. `run_tests/1` — starts ExUnit with a custom `EvalTask.FailureCollector` formatter (a GenServer
   backed by a named ETS `:eval_task_failures` table) that records each failed test's module,
   name, and formatted message; compiles the harness; runs it; returns pass/fail/excluded counts +
   the collected failures.
4. `compute_score/1` — see below.

**Scoring model** (`compute_score/1`):

```
overall = tests · 0.7  +  analysis · 0.2  +  compilation · 0.1     (0.0 if it doesn't compile)

compilation = max(0.0, 1.0 - warnings·0.1)          # zero-warning discipline
tests       = tests_passed / tests_total            # pure pass ratio
analysis    = min(points / 10, 1.0)  where points = sum of:
                @moduledoc present …………… 2
                @spec annotations present … 2
                @doc on public fns ………… 1
                no line > 98 chars ………… 1
                no TODO/FIXME/HACK/XXX …… 1
                no SQL-injection interp. … 1
                credo clean ……………………… 2   (credo_issues hard-coded to [] → effectively free)
```

The `reasons` field explains every deduction. **This rubric is why the canonical solutions all carry
moduledocs, specs, docs, stay under 98 columns, and avoid TODOs** — the doc/spec points are cheap and
banked by default (see §7 house style). `EvalTask.FailureCollector` uses ETS white-box internally so
failures survive across the ExUnit formatter callbacks.

### `scripts/run_all.exs`
Batch driver: `elixir scripts/run_all.exs <solution_filename> [--parallel N]`. Globs
`tasks/*/test_harness.exs`, looks for `<solution_filename>` in each dir (so you can score
`solution.ex` *or* an alternate like `solution_Qwen….ex`), shells out to `eval_task.exs` per task
(sequential or in `Task.async` chunks of N), and writes `results/<task>.json`, a combined
`results/report_<ts>.json`, and a human `results/summary_<ts>.txt` with compile-rate, full-pass rate,
and average score. Tasks lacking the named solution file are reported "missing," not failed.
(`results/` is gitignored.)

### `scripts/validate_harnesses.sh`
A bash sanity check run after adding tasks: for each harness it compiles the `.exs` with ExUnit
loaded and classifies the result — a missing solution/dep module is fine (`OK_NEEDS_MODULE`), but a
genuine `SyntaxError`/`TokenMissingError` (or an unexpected error) is flagged `BROKEN`. It
distinguishes "harness references an undefined module" (expected) from "harness has a real bug."

---

## 6. The authoring pipeline (how tasks are made)

The dataset is grown by three repeatable LLM-driven workflows, each backed by a meta-prompt file and
documented step-by-step in `README.md` ("How to contribute"):

1. **Single-shot task** (`tasks/single_shot_prompt.md`): take a one-line idea from `tasks.md`, ask an
   LLM to expand it into a full prompt *and* a matching test harness (using task 1 as a template).
   Save prompt/harness in a new `{a}_001_{name}_01/` dir, run the candidate solution through
   `eval_task.exs`, fix failures by feeding the JSON report + harness back to the LLM, then commit.

2. **Variations** (`tasks/variation_prompt.md`): feed one task's three files to an LLM and ask for
   **3 meaningfully-different problem variations** (new `b` numbers), plus catalog entries for
   `tasks.md`. This is how e.g. task 1 became four rate-limiter problems.

3. **Fill-in-the-middle subtasks** (`tasks/fill_in_the_middle_prompt.md`): pick good candidate
   functions from a solved module, generate a focused prompt to implement each one, and create `_02+`
   dirs whose `prompt.md` embeds the whole module with the target function replaced by `# TODO` and
   whose `solution.ex` is just that function.

Git history mirrors this exactly: commits read "Three variations of the task N", "Three subtasks
added to task 00X_00Y", "Task NN finished", etc. — a steady hand-curation cadence.

**All three workflows are also fully automated** by `scripts/generate.exs` (code in
`lib/gen_task/**`, design in `docs/04-task-generation-loop.md`). It is a *non-agentic* loop: for
each todo idea in `tasks.md` it drives Claude Opus through a fixed procedure via the `claude -p`
CLI subprocess (subscription-backed, tools off — one completion per call), authoring the base
task, then its variations, then FIM subtasks. Each artifact is graded by shelling out to
`eval_task.exs` in an isolated OS process, repaired on failure (up to `GEN_MAX_RETRIES`), and
**gated on three checks** before promotion: it must be **green**, meet the **house style**
(`@moduledoc`/`@spec`/`@doc`, no TODO, zero compile warnings), and have **every public function**
killed by a `raise`-body mutant (a per-function mutation gate — a harness that tests only some of a
module's public API is rejected). The house-style and per-function gates are skippable
(`GEN_SKIP_QUALITY_GATE`, `GEN_SKIP_PER_FN_MUTATION`). It is **add-only and idempotent**: existing
tasks are never edited or deleted, `tasks.md` inserts are guarded against duplication, and a task
already on disk is skipped — and partially-derived ideas are **topped up** (missing variations /
FIM subtasks are filled on a later run, not skipped). Run it with `mix run scripts/generate.exs
[idea_number]` (see the quick reference below and the README's "Automated generation loop" section
for env knobs); groups 065–131 were produced this way. Design + an audit of the loop's quality/yield
are in `docs/04-task-generation-loop.md` and `docs/05-generation-loop-audit.md`.

---

## Cross-Cutting Conventions & House Style

**Solution files are single-file, self-contained, stdlib-only modules.** Every `solution.ex` defines exactly one top-level module (`CircuitBreaker`, `LRUCache`, `Trie`, `TOTP`) with zero external deps — TOTP explicitly states "Uses only Erlang/OTP and Elixir standard libraries — no external dependencies" (`100_.../solution.ex:8`) and reaches only for `:crypto`, `Bitwise`, `URI`, `Integer`, `String`. OTP primitives come from `use GenServer` (`002`, `041`) or pure functional data (`076` `defstruct`, Saga's fluent builder). No `Application`/`Mix` scaffolding inside solution files.

**Documentation is mandatory and rubric-shaped.** Every canonical solution opens with a `@moduledoc """..."""` (often with ASCII tables — `041/solution.ex:9-13` — state diagrams, and `## Example`/`## Options` sections), every public function has `@doc`, and every public function has a `@spec`. Types are declared with `@type` (`@type name :: GenServer.name()` in `002:19`; `@type state :: %{...}` in `041:68`; `@type t :: %__MODULE__{...}` in `076:19`). Private helpers get `@spec` too (`041:217`, `041:223`). Module bodies are visually sectioned with `# ---` banner comments (`Public API`, `GenServer callbacks`, `Helpers`).

**Determinism via injected clocks / monotonic counters — never wall-clock in hot paths.** CircuitBreaker takes `:clock` as an injectable zero-arity fn defaulting to `System.monotonic_time(:millisecond)` (`002:30-31,74`), stored in state and called as `state.clock.()` (`002:126,177`). LRUCache deliberately avoids clocks entirely, using a monotonic integer `counter` in GenServer state ("never a wall-clock value – so the cache is fully deterministic and testable without any clock mocking", `041:14-17`). TOTP threads time as an explicit `time \\ :os.system_time(:second)` argument (`100:36,59`) so tests can pin timestamps. This injection is the single biggest testability convention.

**Error shapes are tagged tuples; validation is defensive.** Returns are `{:ok, value}` / `{:error, reason}` / bare sentinels like `:miss` (`041:99`) or `:ok`. CircuitBreaker's `execute/1` wraps user funcs in `try/rescue` and normalizes every outcome into `{result, success?}`, converting non-conforming returns to `{:error, {:unexpected_return, other}}` and exceptions to `{:error, exception}` (`002:156-172`) so the GenServer never crashes. Guards gate public entry points: `when is_function(func, 0)` (`002:46`), `when is_binary(word)` on every Trie op (`076:37,67,92,134`), `when is_binary(code)`/`is_integer(code)` in TOTP. Invalid config raises `ArgumentError` early (`041:142-144` max_size; `100:153` bad base32). Struct-pattern function heads (`%__MODULE__{root: root}`) enforce shape at the boundary.

**OTP idioms.** `start_link(opts)` fetches a required `:name` via `Keyword.fetch!` and registers with `name: name` (`002:34-36`, `041:90-92`); optional config via `Keyword.get(opts, k, default)`. State is a plain map built in `init/1`. `@impl true`/`@impl GenServer` annotate callbacks. LRUCache demonstrates the ETS idiom fully: owner GenServer creates named `:set` (`:public, read_concurrency: true`) + `:ordered_set` (`:protected`) tables, allows lock-free direct `:ets.lookup` reads from callers, but serializes all mutations (`:touch`, `:put`, eviction) through `GenServer.call` (`041:105-115,172-210`), plus an explicit `child_spec/0` (`041:47-57`).

**Test-harness conventions.** Every harness is `use ExUnit.Case` with `async: false` when there's shared/named process or ETS state (`002:2`, `041:2`) and `async: true` for pure modules (`076:2`, `070:2`). Fake clocks are built as inline `defmodule Clock do use Agent` with `now/0`, `advance/ms` (`002:5-10`), wired in via `clock: &Clock.now/0`. Processes are started with `start_supervised!({Mod, opts})` for auto-teardown (`002:26`, `041:7`), and name collisions are dodged with `:"lru_#{System.unique_integer([:positive])}"` (`041:6`). Time is advanced by mutating the fake clock (`Clock.advance(5_000)`), never `Process.sleep` / real timers — fully deterministic. Side-effects are observed white-box without extra infra: counting `Agent`s (`002:18-23,110`) or the process dictionary via `track/tracked` helpers (`070:9-14`). No external test deps; assertions use pattern-matching (`assert {:ok, x} = ...`, `assert {:error, :b, :boom, _} = result`). (Note: none of these four harnesses actually call `:sys.get_state`; they assert through the public API — `CircuitBreaker.state/1` — rather than peeking at raw GenServer state, though `eval_task`'s own FailureCollector uses ETS white-box internally.)

**Scoring model (`scripts/eval_task.exs`) the style optimizes for.** `compute_score/1` (`:394`) weights **overall = tests·0.7 + analysis·0.2 + compilation·0.1**, and is hard-zeroed if the solution doesn't compile. Compilation score = `1.0 - warnings·0.1` (`:396-398`) — hence the zero-warning discipline. Tests score = `tests_passed / tests_total` pass ratio (`:402-404`). Analysis (`analyze_source/1:359`, `analysis_checks/1:379`) is a 10-point regex scan normalized to 1.0: `@moduledoc` present (2), `@spec ` present (2), `@doc ` present (1), zero lines >98 chars (1), zero `TODO|FIXME|HACK|XXX` (1), no SQL-injection interpolation `~r/".*#{...}.*FROM|WHERE.*#{/` (1), credo clean (2, stubbed to `credo_issues: []` so effectively free). The canonical solutions visibly target exactly this rubric: every one carries `@moduledoc`+`@spec`+`@doc`, stays under 98 columns, and avoids TODOs — the moduledoc tables and `# ---` section banners cost nothing while banking the 5 doc/spec points. `analysis_score` is capped at 1.0, so the credo stub gives slack.

**Alternate-solution mechanism.** `solution.ex` is the canonical reference; other models' attempts live beside it as `solution_<MODEL>.ex`, the filename encoding the model — e.g. `076_.../solution_Qwen3.5-4B-Q6_K_gguf.ex` (model `Qwen3.5-4B-Q6_K_gguf`). `run_all.exs` takes the solution filename as a positional arg (`elixir scripts/run_all.exs solution_Qwen3.5-4B-Q6_K_gguf.ex`), globs `tasks/*/test_harness.exs`, and scores whichever `<solution_filename>` it finds in each dir against the *same* fixed `test_harness.exs` (`run_all.exs:113-130,166-183`); `eval_task.exs` also accepts `<task> <variation> <solution_file>` (`:168`). Tasks missing that filename are reported as "missing," not failed. The Qwen alternate is a clear negative example of the house style: **no `@moduledoc`, no `@spec`, no `@doc` on the public fns** (only bare descriptive `@doc` strings, and its `@type` uses undefined `char`), and it's functionally broken — `insert/delete` misuse `Enum.reduce` over graphemes while ignoring the accumulator (`solution_Qwen...:20-32`), `delete_char` has an unreachable `cond`-in-pipe and references undefined `trie`/`char.children`, so it would fail compilation/tests and score near zero — illustrating precisely the conventions the canonical solutions encode.

Key files: `/home/car/projects/elixir-sft-dataset/tasks/002_001_circuit_breaker_01/{solution.ex,test_harness.exs}`, `/home/car/projects/elixir-sft-dataset/tasks/041_001_lru_cache_backed_by_ets_01/{solution.ex,test_harness.exs}`, `/home/car/projects/elixir-sft-dataset/tasks/076_001_trie_01/{solution.ex,test_harness.exs,solution_Qwen3.5-4B-Q6_K_gguf.ex}`, `/home/car/projects/elixir-sft-dataset/tasks/100_001_totp_time_based_one_time_password_implementation_01/solution.ex`, `/home/car/projects/elixir-sft-dataset/tasks/070_001_saga_compensating_transaction_coordinator_01/test_harness.exs`, `/home/car/projects/elixir-sft-dataset/scripts/{eval_task.exs,run_all.exs}`.

## The Master Idea Catalogs (tasks.md & tasks_external.md)

These two files are the project's design backlog — flat markdown enumerations of task *ideas*, not implementations. Together they define a single global catalog numbered **1–1000**, partitioned by dependency profile: `tasks.md` holds the pure-stdlib/OTP ideas, `tasks_external.md` holds everything needing a library. The two files never overlap in ID space (558 numbered ideas in the pure file + 442 in the external file = exactly 1000), and they interleave — e.g. IDs 1–15 are pure, 16–30 are external, 31 pure, 32 external, and so on.

### File-level counts

| | tasks.md (pure) | tasks_external.md (external) |
|---|---|---|
| `##` category sections | 60 | 39 |
| `###` headings total | 733 | 461 |
| — numbered base ideas `### N. Name` | 558 (IDs 1–998) | 442 (IDs 16–1000) |
| — variation entries `### Task N - V…` | 48 | 3 |
| — descriptive sub-labels (non-idea) | 127 | 16 |

### The numbering scheme

1. **Base ideas** are `### N. Descriptive Name`, sharing one contiguous 1–1000 space across both files. Each is a self-contained spec paragraph (interface + required behavior + "verify by…" test criteria).
2. **Variation entries** are appended immediately after a base idea as `### Task N - V1/V2/V3 - Descriptive Name`. These are alternative-algorithm spins on a base task (e.g. task 1 "Rate Limiter" → V1 Fixed-Window, V2 Hierarchical, V3 Penalty-Escalation). Only 17 base ideas were multiplied this way: in the pure file, bases **1–13, 15, 31, 33** (16 bases × 3 = 48 variation entries); in the external file, only base **32** (3 entries). Every multiplied base has exactly 3 variations.
3. The remaining ~143 non-numbered `###` headings are structural sub-labels inside the big "Part A/B/C" mega-sections (e.g. `### Reimplementing Testing Tools`, `### LiveView-Specific Tasks`, `### 651–700: Remaining Unique Problems`), not ideas themselves.

So the two files jointly enumerate **1000 base ideas + 51 written variations ≈ 1051 idea specs.**

### Category taxonomy — tasks.md (pure, 60 `## ` sections)

The pure file is organized into families that repeat with "(Continued)" / "(Batch 2/3)" suffixes as ideas were added over time:

- **GenServer / Process-Based Tasks** — the largest early family: 57 + 9 + 5 = ~71 (rate limiters, circuit breakers, token buckets, schedulers, pub/sub, TTL/LRU caches, CRDTs, dedup/coalescers, session stores, worker pools, event sourcing, retry workers, heartbeat monitors)
- **Data Processing / ETL Tasks** — 15 + 8 = ~23 (CSV/JSONL importers, log analyzers, reconciliation, resamplers, tree builders, diff generators)
- **Data Structures / Algorithm Tasks** — 5 + 10 = ~15 (tries, interval/AVL trees, ring/bloom filters, DAG topo-sort, skip lists, union-find, quadtrees, Merkle trees)
- **ETS / In-Memory Storage Tasks** — 5 (ETS LRU, write-through cache, leaderboard, metrics, feature flags)
- **Context / Business Logic Tasks** — 6 + 10 = ~16 (shopping cart, RBAC, promo/coupon engines, inventory, subscriptions, A/B testing, dynamic pricing, SLA tracker)
- **Security / Validation Tasks** — 5 + 5 = ~10 (sanitizers, password policy, TOTP, JWT, secrets, CSP builder)
- **Task/Concurrency Tasks** + **Concurrency Tasks (Batch 2)** — 5 + 5 = ~10 (parallel map, pipelines, work-stealing, fan-out/in, map-reduce, barriers)
- **OTP/Supervision, Caching/Performance, Encoding/Serialization (×2), Networking/Protocol, File/IO, Math/Financial, Text Processing, Error Handling/Resilience, Config/Feature Mgmt, Middleware/Pipeline** — ~4–5 ideas each
- **Domain-Specific Tasks** — 10 (calendar availability, RRULE engine, email/address parsers, semver, unit converter)
- **Part A: Mini Reimplementations of Existing Tools (301–400)** — 46 ("Mini ExMachina", "Mini Mox", "Mini Jason", "Mini GenStage", "Mini Credo", etc.)
- **Part B / Part B Continued: Daily Developer Tasks (356–500)** — 4 + 56 = ~60
- **"Reimplementing …" family** (~26 small sections: Unix/CLI, DB/Storage internals, Network Protocols, Crypto primitives, Web Framework internals, Message Queues, Observability, Data Formats, DevOps, Testing/QA, OTP patterns, Compression, etc.) — ~10 down to 1 each, ~140 total (the "Mini grep/diff/LSM-tree/WAL/HTTP-parser/HMAC/PBKDF2" 500–600 block)
- **Final Batch: Unique Daily-Dev Tasks (631–700)** — 179 headings (the single densest section)
- **Part B: Elixir Library-Specific (831–920)** — 19; **Part C: Erlang/OTP Library-Specific (921–1000)** — 91

### Category taxonomy — tasks_external.md (external, 39 `## ` sections)

- **Phoenix Endpoint / API Tasks** + **Phoenix/API (Continued)** + **(Batch 3)** — 15 + 10 + 10 = ~35 (pagination, search/filter, soft-delete CRUD, bulk create, file upload, idempotent POST, webhook receivers, long-polling, SSE, cursor pagination, ETag, sideloading)
- **Ecto / Database Tasks** + **(Continued)** + **(Batch 3)** + **Advanced Ecto** — 10 + 10 + 5 + 5 = ~30 (multi-tenancy, audit logs, polymorphic assoc, ordered lists, recursive CTEs, DB job queue, soft-delete macros, tsvector search, Ecto.Multi, advisory locks, SCD Type 2, STI)
- **LiveView / Real-time Tasks** (×2) — 5 + 5 = ~10 (debounced search, sortable/infinite tables, form wizards, PubSub feeds, Kanban, collaborative counter, presence chat)
- **Plug / Middleware Tasks** (×2) + **Middleware/Pipeline** — 5 + 5 + 2 = ~12 (request logging, validation, CORS, API-key auth, body-size limit, request-ID, compression, IP allowlist)
- **Integration / External Service Tasks** — 5 (HTTP client wrapper, email service, S3 abstraction, OAuth2, webhook delivery)
- **Telemetry / Observability** — 5; **Data Processing/ETL** (×2) — ~6; **Context/Business Logic (Batch 2)** — 4 + 10 = ~14 (polls, tagging, threaded comments, moderation queues, surveys)
- **Part A: Mini Reimplementations (301–400)** — 17 (Mini Oban, Finch, Ecto.Changeset, Plug, Phoenix.PubSub, Absinthe, Guardian, Swoosh)
- **Part B / Part B Continued (356–500)** — 47 + 77 = ~124 (Phoenix contexts, channels, LiveView components, auth flows, Ecto query patterns)
- **"Reimplementing …" family + Mini SaaS (571–630)** — ~15 (Mini Stripe/SendGrid/Twilio/Algolia/GitHub-webhook/OAuth2-server)
- **Final Batch: Unique Daily-Dev Tasks (631–700)** — 59
- **Part B: Elixir Library-Specific (831–920)** — 79 (Nx tensors/regression/defn, Explorer DataFrames, Broadway, Flow, GenStage, Absinthe, NimbleParsec, Oban, StreamData, Commanded, Ash, Tesla, Req)
- **Part C: Erlang/OTP Library-Specific (921–1000)** — 39

### Implemented vs. idea-only — the realization gap

The `tasks/` directory contains **165 built variation directories** covering only **57 distinct base ideas**, all from the low end of the catalog:

- **Contiguous built ranges:** 001–015, 031–045, 061–064, 070–080
- **Sparse built:** 086, 087, 096–101, and a small high cluster 623–626 (Mini Elasticsearch / Git object store / S3 / Prometheus)

Everything else exists **only as an idea**: the entire 16–30 external-API block, 46–60 (LiveView/Ecto), 81–085 (integrations), the interior gaps 088–095, and the vast **102–622 and 627–1000 span** — including all of Part A/B/C, the "Mini X" reimplementations, the 179-entry "Final Batch," and the entire Nx/Explorer/Broadway/Absinthe library series.

**The gap is stark: 57 of ~1000 catalogued base ideas are realized (~6%), and they are almost entirely confined to IDs ≤101.** The remaining ~940 base ideas plus their would-be variations are pure backlog. Even the written variation specs outrun implementation in places (e.g. base task 14 has three built variation dirs but no `Task 14 - V` idea entries, and conversely the vast majority of the catalog's ideas have no directory at all). These two files are best understood as a ~1000-idea master roadmap of which only the first slice has been turned into actual SFT training tasks.

Key paths: `/home/car/projects/elixir-sft-dataset/tasks/tasks.md`, `/home/car/projects/elixir-sft-dataset/tasks/tasks_external.md`, implemented tasks under `/home/car/projects/elixir-sft-dataset/tasks/NNN_*/`.

---

## Task families in detail

The remainder of this document catalogs every implemented task family — its exact interface, the
algorithm/data structures and OTP constructs it uses, the invariants its harness enforces, and any
noteworthy detail. Families are grouped by task-number range. Within each `_01` dir the three-file
triplet (`prompt.md` / `solution.ex` / `test_harness.exs`) is the authority.

Coverage map of what is implemented:

| Range | Theme |
|---|---|
| 001–015 | OTP process-based: rate limiters, circuit breakers, token buckets, schedulers, event buses, caches, streaming stats, CRDTs, coalescers, stores, worker pools, event sourcing, retry workers, priority queues, monitors |
| 031–034 | Data import, Ecto ingestion, log/file analysis, reconciliation |
| 035–045 | Pure data transforms + ETS-backed modules |
| 061–064 | Hand-rolled concurrency primitives |
| 070–075 | Saga + testing/utility infrastructure |
| 076–080 | Classic functional data structures |
| 086–101 | Business logic + application security |
| 623–626 | Mini clones of real systems (Elasticsearch/Git/S3/Prometheus) |
| 016–025, 102 | `tasks_multifile/`: whole-app Phoenix/Ecto/Plug/OTP features |

## Group 001 — Rate Limiters

Four independent per-key rate-limiting `GenServer` modules of escalating sophistication, all built on the same skeleton: OTP-only (no deps), an injectable `:clock` zero-arity fn (default `fn -> System.monotonic_time(:millisecond) end`) for deterministic testing, optional `:name` registration, and a self-rescheduling memory-reclamation sweep via `Process.send_after(self(), :cleanup, interval)` gated by `:cleanup_interval_ms` (default `60_000`, tests pass `:infinity` to disable and drive `:cleanup` manually with `send/2`). Every `check/*` returns `{:ok, remaining}` on admit or an `{:error, ...}` tuple carrying a `retry_after_ms` on reject, and every family enforces strict per-key independence. All four test harnesses share an identical `Clock` Agent helper (`now/0`, `advance/1`, `set/1`) started via `start_supervised!({Clock, 0})`, and probe internal state with `:sys.get_state/1`. Each family is the "original" problem only (no alternative problem variations); the trailing directory number is a fill-in-the-middle subtask index (`_01` = full module + `test_harness.exs`; `_02+` = single-function FIM with only prompt.md + solution.ex).

### 001_001_rate_limiter — Sliding Window Rate Limiter
- **Interface**: `start_link(opts)` (opts: `:name`, `:clock`, `:cleanup_interval_ms`); `check(server, key, max_requests, window_ms)` with guard `is_integer(max_requests) and max_requests > 0 and is_integer(window_ms) and window_ms > 0`. Returns `{:ok, remaining}` or `{:error, :rate_limited, retry_after_ms}`.
- **Approach**: `GenServer` state `%{keys: %{key => {[timestamp], window_ms}}, clock, cleanup_interval_ms}`. Timestamps stored newest-first (prepend `[now | active]`). On each check, prune via `Enum.filter(timestamps, fn ts -> ts > now - window_ms end)`; admit iff `length(active) < max_requests`; `remaining = max_requests - count - 1`. On reject `retry_after = max(List.last(active) + window_ms - now, 1)` (oldest entry's expiry). Pruned list is persisted even on reject (`put_in(state.keys[key], ...)`).
- **Key invariants tested**: true sliding boundary (3/1000ms exhausted, one slot frees at t=1001 as the t=0 entry expires while t=400/t=800 still block); `retry_after` bounded `0 < r <= window` and roughly time-until-oldest-expires (~700 loose range); keys independent; `max_requests: 1`; very large window (86_400_000); cleanup drops keys whose active list empties (`map_size(state.keys) == 0`).
- **Variations**: 1 (original single-tier sliding window).
- **Subtasks**: 2 FIM — `_02` targets `handle_call({:check,...})`; `_03` targets `handle_info(:cleanup,...)`.
- **Notable**: `schedule_cleanup(:infinity)` is a no-op clause (test hook). Catch-all `handle_info(_msg, state)` prevents crashes. Uses `Enum.filter` (order-independent) rather than `take_while`.

### 001_002_fixed_window_counter — Fixed-Window Counter
- **Interface**: identical shape — `start_link(opts)`; `check(server, key, max_requests, window_ms)` (same guards). Returns `{:ok, remaining}` or `{:error, :rate_limited, retry_after_ms}`.
- **Approach**: absolute discrete windows via `window_index = div(now, window_ms)`, `window_end = (window_index+1)*window_ms`. State `%{counters: %{{key, window_index} => {count, window_end}}, ...}` — O(1) state per active window. Admit iff `count < max_requests`; `remaining = max_requests - new_count`; reject `retry_after = max(window_end - now, 1)` (time to window boundary).
- **Key invariants tested**: abrupt reset at boundary (t=999 fills window 0, t=1000 gives full fresh allowance → the intentional 2×burst across the boundary is asserted as acceptable); mid-window requests don't reset; `retry_after == 700` asserted **exactly** (not a range, unlike sliding); cleanup removes counters with `window_end <= now`.
- **Variations**: 1 (original).
- **Subtasks**: 2 FIM — `_02` targets `handle_call({:check,...})`; `_03` targets `handle_info(:cleanup,...)`.
- **Notable**: prompt explicitly documents and *sanctions* the boundary-burst weakness ("do not try to smooth it out"); moduledoc calls out `2 * max_requests` worst case. Reject path does not mutate state (no counter row created on miss).

### 001_003_hierarchical_limiter — Multi-Tier Sliding Limiter
- **Interface**: `start_link(opts)`; `check(server, key, tiers)` where `tiers` is a non-empty list of `{tier_name :: atom, max_requests, window_ms}`. `validate_tiers!/1` raises `ArgumentError` on malformed tuples. Returns `{:ok, remaining_by_tier}` (map `%{tier_name => remaining}`) or `{:error, :rate_limited, tier_name, retry_after_ms}`.
- **Approach**: single shared per-key timestamp list evaluated against every tier (state `%{keys: %{key => {[ts_newest_first], widest_window_seen}}}`). `widest_window = Enum.max(windows)`; lazily prune with `Enum.take_while(ts, & &1 > now - widest_window)` (relies on newest-first sorted order). `evaluate_tiers/3` counts in-window entries per tier via nested `take_while`; if all pass, records `[now | active]` and builds remaining map (`max - count - 1` per tier); if any fail, records NO timestamp (rejected requests consume no budget) and reports the **tightest** = `Enum.max_by` on longest `retry_after` among failing tiers.
- **Key invariants tested**: single-tier ≡ plain sliding window; request admitted only if every tier has capacity; inner tier (per_sec) can reject while outer has headroom and vice-versa (per_min binding across bursts); rejections don't consume budget (10 rejects then per_min shows only 2 used); when both saturate, reports the longer-wait tier (`:per_min`, `1_000 < r <= 60_000`); three-tier real-world stack (10/s, 100/min, 1000/hr); cleanup prunes to widest window and drops emptied keys.
- **Variations**: 1 (original).
- **Subtasks**: 3 FIM — `_02` targets `handle_call({:check,...})`; `_03` targets `handle_info(:cleanup,...)`; `_04` targets the private `evaluate_tiers/3`.
- **Notable**: "tightest" is deliberately defined as *longest* retry_after (the wait the caller actually faces), not the strictest tier — subtle and explicitly tested. Correctness of `take_while` pruning depends on the monotonic-clock newest-first ordering invariant.

### 001_004_penalty_escalation — Escalating-Cooldown Limiter
- **Interface**: `start_link(opts)`; `check(server, key, max_requests, window_ms, penalty_ladder)` where `penalty_ladder` is a non-empty list of positive-int cooldown ms indexed by strike count (entries validated, raise `ArgumentError` otherwise). Three outcomes: `{:ok, remaining}`; `{:error, :rate_limited, retry_after_ms, strike_count}` (limit exceeded, strike recorded); `{:error, :cooling_down, retry_after_ms, strike_count}` (active cooldown, no new strike — retries don't compound).
- **Approach**: per-key entry map `%{timestamps, strikes, last_strike_at, cooldown_end}` (`empty_entry/0`). Check flow: (1) `decay_strikes/3` — forgive `div(now - last_strike_at, window_ms*10)` strikes, `window_ms*10` = hardcoded decay period; if forgiven ≥ strikes reset to `empty_entry()`, else subtract and advance `last_strike_at`, clearing stale `cooldown_end`; (2) expire cooldown if `cooldown_end <= now`; (3) if cooldown still active → `:cooling_down`; else `evaluate_window/7` runs the sliding-window check. On reject: `new_strikes = strikes+1`, `cooldown_ms = ladder_value(ladder, new_strikes)` (`ladder_value` clamps index at `length(ladder)-1`), `retry_after = max(max(window_retry, cooldown_ms), 1)`, store `cooldown_end = now + retry_after`, do NOT add `now` to timestamps.
- **Key invariants tested**: strike recorded on first reject (returns count `1`, `retry_after >= 1_000` first-ladder rung); `:cooling_down` after window clears but cooldown active (`long_ladder [5_000,30_000]`, retries stay at strike 1); ladder walk 1→2→3 (`retry >= 5_000`, `>= 30_000`); ladder clamps beyond length (strike 3 reuses last `2_000`); decay after `window_ms*10` (=10_000) returns to strike 1; multi-strike decays one-at-a-time; per-key isolation; cleanup keeps entries with cooldown/strikes/timestamps.
- **Variations**: 1 (original).
- **Subtasks**: 4 FIM — `_02` targets `handle_call({:check,...})`; `_03` targets `evaluate_window/7`; `_04` targets `decay_strikes/3` (main clause; the `strikes: 0` and `last_strike_at: nil` guard clauses live in the surrounding module); `_05` targets `handle_info(:cleanup,...)`.
- **Notable**: solution is visibly the product of iterative debugging — comments carry emoji/self-referential fix notes (`# ✅ FIX: expire cooldown`, `# 🔑 clear stale cooldown`, "Fixed: Align stored state with returned value"). Suspicious cleanup line: `active = Enum.take_while(entry.timestamps, fn ts -> ts > now end)` keeps only *future* timestamps, effectively dropping all real (past) timestamps since `window_ms` is unavailable in `:cleanup`; the harness only asserts a weaker "fresh key behaves cleanly" property so it passes regardless. This is the most stateful/edge-case-heavy family in the group.

## Group 002 — Circuit Breakers

Four self-contained Elixir `GenServer` circuit-breaker tasks, each a variation on the closed/open/half-open resilience pattern but differing in the **trip-decision mechanism** (consecutive count vs. rolling error-rate vs. leaky-bucket) and **recovery model** (instant vs. progressive ladder). All share a near-identical skeleton: `start_link/1` with keyword opts, a synchronous `call(name, func)` that runs a zero-arity protected function through the breaker, `state/1`, `reset/1`, and — critically — an **injected `:clock`** (zero-arity `-> ms`, default `System.monotonic_time(:millisecond)`) so tests drive time deterministically via a fake `Clock` Agent. Outcome classification is uniform everywhere: `{:ok, v}`=success; `{:error, r}`, a raised exception (caught, returned as `{:error, exception_struct}`, never crashing the server), or any other return shape = failure. No external deps; each family is one file. Each family has one original task with a `test_harness.exs` (`_01`) plus several fill-in-the-middle (FIM) subtasks (`_02+`) that blank out one private function with `# TODO`; there are **no `b`-variation problem rewrites** in this group (all dirs share `b=00X` per family, differing only by subtask number `d`).

### 002_001_circuit_breaker — Three-State Circuit Breaker (consecutive-count)
- **Interface**: `CircuitBreaker.start_link(opts)` opts `:name` (required), `:failure_threshold` (5), `:reset_timeout_ms` (30_000), `:half_open_max_probes` (1), `:clock`. `call(name, func)`, `state(name) :: :closed|:open|:half_open`, `reset(name) :: :ok`. Errors surfaced as `{:error, :circuit_open}` when open/over-probe-limit.
- **Approach**: `use GenServer`; single flat state map `%{circuit_state, failure_count, failure_threshold, reset_timeout_ms, half_open_max_probes, clock, opened_at, probe_count}`. `handle_call({:call, func}, ...)` dispatches on `circuit_state` to `handle_closed/handle_open/handle_half_open`. Helper `execute/1` (try/rescue), `trip_open/1` (sets `opened_at = clock.()`, zeroes counts), `reset_to_closed/1`. Consecutive **failure_count resets to 0 on any success** in closed; trips when `new_count >= failure_threshold`. Open→half-open is **lazy inside `handle_open`** (checks `elapsed >= reset_timeout_ms`, then delegates to `handle_half_open` letting that first call through as the probe). Note: unlike the other three families, `state/1` here does NOT lazily expire the open timer — the transition only happens on a `call`.
- **Key invariants tested**: starts closed; single failure keeps closed (threshold 3 in tests); success resets consecutive count; open rejects without invoking func (Agent counter stays 0); `Clock.advance(4_999)` stays open, `+1`=5000 lets probe through; successful probe→closed, failed probe→open with restarted timer + immediate re-block; `reset` from open→closed and from closed zeroes counter; full lifecycle closed→open→half-open→open→half-open→closed.
- **Variations**: 1 (original only).
- **Subtasks**: 4 FIM — `_02` `handle_closed/2`, `_03` `handle_open/2`, `_04` `handle_half_open/2`, `_05` `execute/1`.
- **Notable**: raise returns `{:error, exception}` (the struct itself). `execute/1` maps non-`{:ok}`/`{:error}` returns to `{:error, {:unexpected_return, other}}`. FIM prompts embed the full module with the target function replaced by `# TODO`.

### 002_002_rolling_window_error_rate_cb — Rolling-Window Error-Rate Breaker (Hystrix-style)
- **Interface**: `RollingRateCircuitBreaker.start_link(opts)` opts `:name`, `:window_size` (20), `:error_rate_threshold` float in (0.0,1.0] (0.5), `:min_calls_in_window` (10), `:reset_timeout_ms` (30_000), `:half_open_max_probes` (1), `:clock`. Same `call/state/reset` surface; `state` message key is `:get_state`.
- **Approach**: state map `%{state, outcomes, opened_at, probes_in_flight, clock, config}` where `config` is a nested map. `outcomes` is a **count-based list of `:ok|:error` atoms, newest-first, truncated via `[outcome | outcomes] |> Enum.take(window_size)`**. Trip predicate `should_trip?/2`: `total>=min_calls_in_window AND errors/total >= error_rate_threshold` (via `Enum.count(&(&1==:error))`). Distinct from family 001: uses lazy `maybe_expire_open/1` (called at top of every `{:call}` and `:get_state`) to flip open→half-open when timer elapses. **Window is wiped `[]` on every transition** (trip, probe success→closed, probe fail→open, manual reset). `execute_and_classify/1` returns `{:ok|:error, reply}`.
- **Key invariants tested**: 20 successes stay closed; 3/10 errors (30%) stays closed; exactly 3/6=50% trips; 100% error but only 5<6 min_calls stays closed then 6th trips; **strict 50/50 alternation trips** (the whole point vs. consecutive-count); rolling eviction can keep closed at 4/10 then trip at 5/10; open rejects (uses `refute_received`); open→half-open exactly at `reset_timeout_ms`; probe success→closed with empty window; probe fail→open with fully restarted timer; raise `%RuntimeError{message: "boom"}` counts, 6 raises trip; reset clears window.
- **Variations**: 1.
- **Subtasks**: 3 FIM — `_02` `should_trip?/2`, `_03` `execute_and_classify/1`, `_04` `execute_in_closed/2`.
- **Notable**: motivation explicitly cites Netflix Hystrix; `min_calls_in_window` floor prevents 1/1=100% early trip.

### 002_003_progressive_recovery_cb — Four-State Progressive-Recovery Breaker
- **Interface**: `ProgressiveRecoveryCircuitBreaker.start_link(opts)` opts `:name`, `:failure_threshold` (5), `:reset_timeout_ms` (30_000), `:half_open_max_probes` (1), `:recovery_stages` (default `[{5,0},{15,1},{30,2}]`), `:clock`. `state(name) :: :closed|:open|:half_open|:recovering`; plus `call/reset`.
- **Approach**: Adds a `:recovering` state between half-open and closed to stop flapping — a successful probe enters `:recovering` at stage 0 rather than closing immediately. State map adds `recovery_stage`, `stage_calls`, `stage_failures` (plus `failure_count`, `opened_at`, `probes_in_flight`). Closed trip logic identical to family 001 (consecutive `failure_threshold`). `recovery_stages` is a list of `{calls_required, failures_tolerated}` tuples; `execute_in_recovering/2` increments stage counters, reads limits via `Enum.at(recovery_stages, recovery_stage)`, then a `cond`: `stage_failures > tolerated`→`:open` (restart timer, reset stage to 0); `stage_calls >= required`→`advance_stage/2` (next stage w/ fresh counters, or `:closed` if final); else stay. `init` raises `ArgumentError` on empty `recovery_stages`. Lazy `maybe_expire_open/1`.
- **Key invariants tested** (test ladder `[{3,0},{5,1},{10,2}]`, threshold 3): closed passthrough; 3 consecutive failures trip; success resets consecutive count; open rejects; **probe success→`:recovering` NOT `:closed`**; clearing all three stages (3, then 5, then 10 calls) →`:closed`; 1 failure inside stage-1 tolerance stays recovering; single failure in stage-0 (zero tolerance)→`:open`; 2nd failure in stage-1→`:open`; reopen from recovering restarts reset timer; raise in recovering counts as stage failure→`:open`; reset from open/recovering zeroes all counters.
- **Variations**: 1.
- **Subtasks**: 4 FIM — `_02` `execute_in_closed/2`, `_03` `execute_in_half_open/2`, `_04` `execute_in_recovering/2`, `_05` `advance_stage/2`.
- **Notable**: `@default_recovery_stages` module attribute; ladder gives progressively more evidence at progressively higher permitted failure counts; every recovering call executes (no traffic sampling/rejection during recovery).

### 002_004_leaky_bucket_failure_cb — Leaky-Bucket Failure Breaker
- **Interface**: `LeakyBucketCircuitBreaker.start_link(opts)` opts `:name`, `:bucket_capacity` (5.0), `:leak_rate_per_sec` (1.0), `:failure_weight` (1.0), `:reset_timeout_ms` (30_000), `:half_open_max_probes` (1), `:clock`. Adds inspection API **`bucket_level(name) :: float()`** (applies pending leak before returning) on top of `call/state/reset`.
- **Approach**: Failures add `failure_weight` drops; drops leak continuously at `leak_rate_per_sec`. State map `%{state, bucket_level (float), last_update_at, opened_at, probes_in_flight, clock, config}`. Core helper `apply_leak/1`: `leak = elapsed_ms * leak_rate_per_sec / 1000; bucket_level = max(0.0, bucket_level - leak)`, advances `last_update_at` to now — applied **lazily** at start of `execute_in_closed/2` and in the `:bucket_level` handler (no periodic timer). Closed: leak first, run func, on failure add weight; trip to `:open` (and **zero bucket on trip**) when `new_level >= bucket_capacity`. `config` coerces all numeric opts to floats via `* 1.0` so integer opts work. Lazy `maybe_expire_open/1`; probe success→closed with empty bucket, resetting `last_update_at`.
- **Key invariants tested**: bucket starts 0.0; each failure +1.0; successes add nothing; leaks 3.0→2.0 after 1s, →0.0 after 3s; never below 0 even after huge idle; partial-second (500ms→0.5) leak; burst of 5 trips; 1 failure/2s outpaced by 1/s leak stays closed over 20 iters; trips on fresh burst after quiet period; intermingled successes don't reduce bucket (4 fails + ok + fail trips at 5.0); `failure_weight: 3.0` (9.0 under 10 cap, 4th=12 trips); all-integer opts coerced (`cap 3, rate 2, weight 1`); open rejects; open→half-open at timeout; probe success→closed empty bucket; probe fail→open restarted timer; 5 raises trip; reset clears bucket.
- **Variations**: 1.
- **Subtasks**: 3 FIM — `_02` `apply_leak/1`, `_03` `execute_in_closed/2`, `_04` `execute_in_half_open/2`.
- **Notable**: motivation cites Cisco-router error-rate detection; all bucket arithmetic float; two harness tests re-`start_link` extra breakers (`:weighted_cb`, `:int_cb`) reusing the single supervised `Clock` (comments note removed duplicate `start_supervised!`).

Key files (originals with harnesses): `/home/car/projects/elixir-sft-dataset/tasks/002_001_circuit_breaker_01/`, `/home/car/projects/elixir-sft-dataset/tasks/002_002_rolling_window_error_rate_cb_01/`, `/home/car/projects/elixir-sft-dataset/tasks/002_003_progressive_recovery_cb_01/`, `/home/car/projects/elixir-sft-dataset/tasks/002_004_leaky_bucket_failure_cb_01/` (each has prompt.md, solution.ex, test_harness.exs).

## Group 003 — Token Buckets

Four independent per-key rate-limiter GenServers, all sharing a common design language: keyed buckets in a `%{name => data}` map, **lazy time-based refill** computed on each call (never per-bucket timers), an **injectable `:clock`** (`(-> integer_ms)`, defaults to `System.monotonic_time(:millisecond)`) for deterministic tests, a `retry_after_ms` on rejection (positive-integer ceiling), and a periodic `Process.send_after(self(), :cleanup, interval)` sweep (configurable `:cleanup_interval_ms`, default 60_000; tests pass `:infinity` to disable) that evicts buckets indistinguishable from fresh ones. Token counts are floats (fractional refill), `remaining` returned as integer floor/`trunc`. Every test file embeds an identical `Clock` Agent (`start_link`, `now/0`, `advance/1`, `set/1`) registered under `__MODULE__`, `use ExUnit.Case, async: false`, and pokes internals via `:sys.get_state/1` and `send(pid, :cleanup)`. No external deps; OTP stdlib only. Each family is a single problem (variation `001`); the `_NN` suffix is the **subtask** index, not an alt-variation — only `_01` ships a `test_harness.exs`, higher subtasks are fill-in-the-middle (prompt embeds full module with one function stubbed `# TODO`, `solution.ex` is just that function body).

### 003_001_leaky_bucket_token_dispenser — Leaky Bucket Token Dispenser

- **Interface**: `LeakyBucket.start_link(opts)` (`:clock`, `:name`, `:cleanup_interval_ms`=60_000, `:cleanup_ttl_ms`=300_000); `LeakyBucket.acquire(server, bucket_name, capacity, refill_rate, tokens \\ 1)` → `{:ok, remaining}` | `{:error, :empty, retry_after_ms}`.
- **Approach**: `use GenServer`. Nested `defstruct` modules `State{clock, cleanup_interval_ms, cleanup_ttl_ms, buckets: %{}}` and `Bucket{tokens, last_access}` (both `@enforce_keys`). Lazy refill `new = min(capacity, old + elapsed_ms*refill_rate/1000)` in private `refill/4` using `max(now-last_access, 0)`. Fresh bucket starts **full** at `capacity*1.0`. `retry_after_ms = ceil(deficit/refill_rate*1000)`, `deficit = tokens - bucket.tokens`. `extract_gen_opts/1` splits `:name` for registration. `schedule_cleanup(:infinity)` is a no-op clause.
- **Key invariants tested**: new bucket full; drain-to-zero then reject; refill proportional to elapsed time (5 tok/s → +5 after 1000ms, partial 500ms → +5 at 10/s); never exceeds capacity after huge idle; `retry_after` within ±100–200ms tolerance bands and accounts for multi-token + fractional balance; bucket independence/interleaving; `capacity 1`, high refill (1000/s capped), request > capacity always fails; cleanup drops buckets idle > `cleanup_ttl_ms` (empties `state.buckets`), keeps recently-touched. Note: rejection path still updates `last_access` (touched) so refilled tokens/eviction aren't lost.
- **Variations**: 1 (original only).
- **Subtasks**: 2 fill-in — `_02` = `handle_call({:acquire,...})`; `_03` = `handle_info(:cleanup,...)`.
- **Notable**: uses `floor/1` for `remaining` (vs `trunc/1` elsewhere in group); catch-all `handle_info(_msg, state)`.

### 003_002_gcra — GCRA / Theoretical Arrival Time

- **Interface**: `GcraLimiter.start_link(opts)` (`:clock`, `:name`, `:cleanup_interval_ms`=60_000, `:cleanup_idle_ms`=300_000); `GcraLimiter.acquire(server, bucket_name, rate_per_sec, burst_size, tokens \\ 1)` → `{:ok, remaining}` | `{:error, :rate_exceeded, retry_after_ms}`. Guard clause: `rate_per_sec` number > 0, `burst_size`/`tokens` positive integers.
- **Approach**: state is `%{buckets: %{name => tat_float}, clock, cleanup_interval_ms, cleanup_idle_ms}` — **single scalar TAT per bucket**, not `{tokens, last_refill}`. Per call: `emission_interval = 1000/rate_per_sec`; `dvt = burst*emission_interval`; `tat = Map.get(buckets, bucket, now*1.0)`; `new_tat = max(now, tat) + tokens*emission_interval`; `earliest_admit = new_tat - dvt`. Admit iff `earliest_admit <= now`, store `new_tat`, `remaining = max(trunc((dvt-(new_tat-now))/emission_interval), 0)`. Reject → **do NOT update TAT**, `retry_after = ceil_positive(earliest_admit-now)` (min 1). Cleanup drops buckets where `now - tat >= cleanup_idle_ms`.
- **Key invariants tested**: fresh bucket admits full burst back-to-back; steady-state one admit per `emission_interval` after burst; **`max(now,tat)` trap** — 10_000_000ms idle still admits only `burst` (no unbounded credit); **no-TAT-advance-on-reject trap** — 50 spam rejects then +200ms still admits one; independent TATs; multi-token deducts all / over-burst rejected without mutating TAT; `retry_after` within emission interval; fractional rates (0.5 req/s → 2000ms interval); cleanup with `cleanup_idle_ms: 1_000`.
- **Variations**: 1.
- **Subtasks**: 2 fill-in — `_02` = `handle_call({:acquire,...})` (GCRA core math); `_03` = `handle_info(:cleanup,...)`.
- **Notable**: prompt explicitly enumerates the two classic GCRA pitfalls; `ceil_positive/1` helper (trunc+bump, `max(_,1)`).

### 003_003_lease_based_bucket — Lease-Based Bucket (reserve / complete / cancel)

- **Interface**: `LeaseBucket.start_link(opts)` (`:clock`, `:name`, `:cleanup_interval_ms`=60_000); `acquire_lease(server, bucket, capacity, refill_rate, tokens, lease_timeout_ms)` → `{:ok, lease_id, remaining}` | `{:error, :empty, retry_after_ms}` (guard also enforces `tokens <= capacity`); `release(server, bucket, lease_id, outcome)` with `outcome in [:completed, :cancelled]` → `:ok` | `{:error, :unknown_lease}`; `active_leases(server, bucket)` → `{:ok, count}` (`{:ok, 0}` unknown).
- **Approach**: per-bucket map `%{free: float, capacity, refill_rate, last_update_at, leases: %{lease_id => {tokens, expires_at}}}`. `lease_id = make_ref()` (opaque `reference()`). Central `refill_and_expire(bucket, now)` applies lazy refill AND drops leases where `expires_at <= now` — **expired leases treated as `:completed`, tokens NOT refunded** (pessimistic, anti-exploit); called at the top of every acquire/release/active_leases/cleanup. `:cancelled` refunds `min(capacity, free+tokens)`; `:completed` just deletes. `acquire_lease` multiplies `refill_rate*1.0`. `get_bucket/5` lets capacity/rate be updated mid-stream. Cleanup drops buckets with `map_size(leases)==0 and free >= capacity`.
- **Key invariants tested**: reserve deducts + returns ref; over-free-balance rejected; `:cancelled` refunds (full balance restored), `:completed` keeps consumed; unknown/known-bucket-unknown-lease and double-release both `:unknown_lease`; expired lease vanishes without refund but elapsed refill still applies (2→3.5 over 1.5s); one bucket op expires *other* buckets' due leases; lazy refill + cap; multiple independent leases with mixed outcomes; cleanup drops refilled-lease-free buckets, keeps ones with long (3_600_000ms) leases.
- **Variations**: 1.
- **Subtasks**: 3 fill-in — `_02` = private `refill_and_expire/2`; `_03` = `handle_call({:acquire_lease,...})`; `_04` = `handle_call({:release,...})`.
- **Notable**: only family with a mutation API (release) and lease timeouts; `remaining` uses `trunc/1`.

### 003_004_shared_pool_bucket — Shared-Pool (Two-Level) Bucket

- **Interface**: `SharedPoolBucket.start_link(opts)` — **required** `:global_capacity` (pos int) + `:global_refill_rate` (pos number) via `Keyword.fetch!`, plus `:clock`, `:name`, `:cleanup_interval_ms`=60_000; `acquire(server, bucket_name, key_capacity, key_refill_rate, tokens \\ 1)` → `{:ok, key_remaining, global_remaining}` | `{:error, :key_empty | :global_empty, retry_after_ms}`; `global_level(server)` → `{:ok, int}`; `key_level(server, bucket_name, key_capacity, key_refill_rate)` → `{:ok, int}` (`{:ok, key_capacity}` if unseen, **without creating** the bucket).
- **Approach**: two levels — per-key buckets `%{free, capacity, refill_rate, last_update_at}` in `state.buckets`, and the **global pool at top level** (`global_free`, `global_capacity`, `global_refill_rate`, `global_last_update_at`), never in the buckets map. Both use same lazy formula; `refill_global/2` and `get_and_refill_bucket/5` applied to both **before** evaluating drain. Atomic: on reject **nothing drained from either level** (refilled state still persisted so clock stays current). Precedence via `cond`: check `bucket.free < tokens` → `:key_empty` **first** (even if global also short), then `state.global_free < tokens` → `:global_empty`, else drain both. `retry_after = ceil_positive(deficit*1000/rate)` per offending level. Cleanup projects each bucket's refill and drops those `>= capacity`; **global pool never dropped**.
- **Key invariants tested**: both levels drain on success; global drains across different keys; per-key exhaustion returns `:key_empty` and leaves global/other keys intact; rejected acquire drains nothing; global exhaustion → `:global_empty` when per-key has room (carol untouched); **both-empty precedence** (global_capacity 2) reports `:key_empty` not `:global_empty`; independent lazy refill + caps on both levels; multi-token math; `key_level` on unknown returns capacity without creating bucket; cleanup empties `buckets` but keeps global (refilled to 10).
- **Variations**: 1.
- **Subtasks**: 3 fill-in — `_02` = `handle_call({:acquire,...})` (two-level cond); `_03` = private `get_and_refill_bucket/5`; `_04` = `handle_info(:cleanup,...)`.
- **Notable**: only family that configures limits (global) at `start_link` and requires opts; per-key capacity/rate still passed per-`acquire` (not stored at creation), hence `key_level` needs them as args.

Files: full specs in `/home/car/projects/elixir-sft-dataset/tasks/003_001_leaky_bucket_token_dispenser_01/`, `.../003_002_gcra_01/`, `.../003_003_lease_based_bucket_01/`, `.../003_004_shared_pool_bucket_01/` (each `prompt.md` + `solution.ex` + `test_harness.exs`).

## Group 004 — Schedulers

Four self-contained job-scheduler `GenServer` modules, each a single-file OTP solution using only the standard library. All share an identical architectural skeleton: state is `%{jobs: %{name => job_map}, clock, tick_interval_ms}`; a zero-arity **injected `:clock`** returning `NaiveDateTime` makes time deterministic; a poll loop driven by `Process.send_after(self(), :tick, tick_interval_ms)` (default `1_000`; `:infinity` disables auto-ticking so tests drive `:tick` by hand); job MFAs are executed via `apply(mod, fun, args)` wrapped in `try/rescue/catch` so a crashing job never kills the server. They differ only in the **schedule representation and the next-run math**: cron expressions (001), fixed drift-free intervals (002), one-shot exponential-backoff retries (003), and calendar-aware rules (004). Every family's `_01` dir is the full single-shot task (has `test_harness.exs`); `_02+` dirs are fill-in-the-middle subtasks (prompt.md embeds the whole module with one private function replaced by `# TODO`, solution.ex is just that function). Tests use ExUnit `async: false`, an `Agent`-based fake `Clock` (`now/advance/set`), and either an `Agent` `JobTracker`/`Flaky` or `send(test_pid, tag)` sinks; ticks are synchronized via `send(pid, :tick); :sys.get_state(pid)`.

### 004_001 — Job Scheduler with Cron-like Expressions

- **Interface** (module `Scheduler`): `start_link(opts)` (opts `:clock`, `:name`, `:tick_interval_ms`); `register(server, name, cron_expression, {mod, fun, args})` → `:ok | {:error, :invalid_cron} | {:error, :already_exists}`; `unregister(server, name)` → `:ok | {:error, :not_found}`; `jobs(server)` → `[{name, cron_expression, next_run}]`; `next_run(server, name)` → `{:ok, ndt} | {:error, :not_found}`.
- **Approach**: 5-field cron string (minute 0–59, hour 0–23, day 1–31, month 1–12, weekday 0–6 with 0=Sunday). Parser (`parse_cron`→`parse_field`→`parse_part`→`parse_range_or_star`/`parse_range_or_value`) supports `*`, int, comma-lists, `a-b` ranges, `*/step` and `a-b/step`; each field compiled to a `MapSet` of ints (`@field_ranges`, `@field_order`). Next-run via `next_run_time`→`scan/3`: truncate seconds to 0, add 60s, then minute-by-minute forward scan with jumps (`advance_to_next_month`, `next_day`, `next_hour`) checking month→day→weekday→hour→minute in order; `@max_iterations 2_200_000` guard raises if no match. `day_of_week/1` converts Elixir's `Date.day_of_week` (Mon=1..Sun=7) so Sunday→0. On `:tick`, jobs with `next_run <= now` fire and recompute from `now`.
- **Key invariants tested**: out-of-range values rejected (minute 60, hour 25, weekday 7, too few fields); duplicate names; recurrence advances (`0 * * * *` 11:00→12:00); `*/15`→{0,15,30,45}; `10-30/10`→{10,20,30}; day-of-week scheduling (Sun→next Sunday Jan 11, Wed→Jan 7 then Jan 14); leap-year `0 0 29 2 *` skips to **2028-02-29**; no double-fire on repeated tick; two jobs same minute both fire; unregister prevents firing.
- **Subtasks** (4): `_02` `scan/3` (field-priority advance loop); `_03` `parse_part/3` (step handling); `_04` `parse_range_or_value/3` (single/range); `_05` `parse_field/3` (comma-split reduce into MapSet).
- **Notable**: step semantics keep values whose offset from the range start is divisible by step (`rem(v - start, step) == 0`), not strict modulo-0. Only family with a full standalone cron parser and minute-scan (vs. calendar math).

### 004_002 — IntervalScheduler (drift-free)

- **Interface** (module `IntervalScheduler`): same shape as 001 but `register(server, name, interval_spec, mfa)` where `interval_spec = {:every, n, unit}`, `unit ∈ :seconds|:minutes|:hours|:days`, `n` positive int → `{:error, :invalid_interval}` otherwise; `jobs` returns `{name, interval_spec, next_run}`.
- **Approach**: `parse_interval/1` converts spec to `interval_s` seconds (×60/×3600/×86400). Registration captures immutable `started_at` anchor from clock. **Drift-free** `compute_next_run(started_at, interval_s, now)`: `elapsed = NaiveDateTime.diff(now, started_at, :second); n = max(1, div(elapsed, interval_s) + 1); started_at + n*interval_s`. On `:tick`, due jobs execute and reschedule from the **anchor**, not from execution time.
- **Key invariants tested**: first fire at `t0 + interval`; late tick (t0+61s) → next is t0+120s not t0+121s (no cumulative drift); big skip (t0+250s) → exactly **one** fire, next = t0+300s (**no catch-up replay** of missed 60/120/180/240 boundaries); steady-state alignment `N = div(i*11,10)+1` over 5 ticks; unit conversions (300/7200/86400s); crashing job (`{:error,:invalid_interval}` specs `{:every,0,...}`, `{:every,-5,...}`, `:fortnights`, string spec) rejected; crashing job survives and still advances; unregister stops firing.
- **Subtasks** (2): `_02` `compute_next_run/3` (the drift-free formula); `_03` `parse_interval/1` (4 unit clauses + fallthrough).
- **Notable**: `safe_execute` returns `:crashed` on failure but return value ignored — interval jobs fire regardless of outcome (contrast 003). The entire point is anchor-relative scheduling to avoid drift and replay.

### 004_003 — RetryScheduler (backoff)

- **Interface** (module `RetryScheduler`): `start_link(opts)`; `schedule(server, name, run_at, {mod,fun,args}, opts \\ [])` where `run_at` is a `NaiveDateTime` and `opts` may set `:max_attempts` (default 3, **total** attempts incl. first), `:base_delay_ms` (default 1_000), `:backoff_factor` (default 2.0, must be ≥ 1.0) → `:ok | {:error, :already_exists} | {:error, :invalid_opts}`; `cancel(server, name)` → `:ok | {:error, :not_found}` (valid in any state, incl. terminal); `status(server, name)` → `{:ok, status, attempts_so_far} | {:error, :not_found}`, status `:pending|:completed|:dead`; `jobs(server)` → `[{name, status, next_attempt_at, attempts_so_far}]`.
- **Approach**: one-shot jobs with lifecycle `:pending → :completed` (success) or `:pending → :dead` (retries exhausted); terminal jobs retained for inspection, never re-run. On `:tick`, only `status == :pending && next_attempt_at <= now` are picked. `process_attempt/2`: increments `attempts_so_far`; success (`safe_execute` maps `:ok`/`{:ok,_}`→`:success`, everything else incl. `:error`/`{:error,_}`/weird returns/raise/throw→`:failure`) → `:completed`; failure with `attempts >= max_attempts` → `:dead`; else stay `:pending` with `next_attempt_at = now + round(base_delay_ms * backoff_factor^(attempts-1))` ms. `validate_opts` enforces integer `max_attempts ≥ 1`, integer `base_delay_ms ≥ 0`, number `backoff_factor ≥ 1.0` (coerced `* 1.0`).
- **Key invariants tested**: outcome classification (all 8 return/exception shapes); backoff geometry (1000; then 100→300→700 cumulative for factor 2; `:dead` at max_attempts); flaky "fail twice then succeed" ends `:completed` with 3 attempts; `run_at` in past fires next tick, future respected; `:dead`/`:completed` never re-execute; cancel stops retries; invalid opts (`max_attempts: 0`, `backoff_factor: 0.5`, `base_delay_ms: -1`).
- **Subtasks** (3): `_02` `process_attempt/2` (success/dead/backoff branches); `_03` `safe_execute/1` (outcome classifier); `_04` `validate_opts/1`.
- **Notable**: only non-recurring family (bounded lifecycle, terminal states). Delays are in **milliseconds** (uses `NaiveDateTime.add(now, delay_ms, :millisecond)`); test `Clock.advance_ms/1`. `schedule/5` guard requires `%NaiveDateTime{} = run_at`. Test harness `Flaky` module has an explicit `use Agent` comment noting a child_spec fix.

### 004_004 — CalendarScheduler

- **Interface** (module `CalendarScheduler`): same shape as 002 but `register(server, name, rule, mfa)` → `:ok | {:error, :invalid_rule} | {:error, :already_exists}`; `jobs` returns `{name, rule, next_run}`. Four rule tuples exactly: `{:nth_weekday_of_month, n(1..4), weekday, {h, m}}`; `{:last_weekday_of_month, weekday, {h, m}}`; `{:nth_day_of_month, day(1..31), {h, m}}`; `{:last_day_of_month, {h, m}}`. `weekday ∈ :monday..:sunday` (`@weekdays` maps to ISO 1..7), `h ∈ 0..23`, `m ∈ 0..59`.
- **Approach**: `valid_rule?/1` clauses with guards for each tuple shape. Next-run is **calendar-walking, not minute-scanning**: `compute_next_run(rule, after_ndt)` → `walk_months/5` starting at `{after.year, after.month}` with a **60-month budget** (raises if exhausted). Per month `target_in_month/3` computes the candidate: nth_weekday uses `Date.day_of_week(first_of_month)`, `days_to_first = rem(target_dow - first_dow + 7, 7)`, `nth_day = 1 + days_to_first + (n-1)*7` (`:no_match` if `> days_in_month`); last_weekday walks back from last day (`steps_back = rem(last_dow - target_dow + 7, 7)`); nth_day valid iff `day <= Calendar.ISO.days_in_month`; last_day uses `days_in_month` directly. First candidate strictly `> after_ndt` wins; else `bump_month` (Dec→Jan next year).
- **Key invariants tested**: first Monday Jan 2025 = Jan 6; second Tuesday = Jan 14; advance to next month after target passes (→ Feb 3); last Friday Jan = Jan 31; last Sunday Feb 2025 = Feb 23; 15th at noon; **`nth_day_of_month, 31` skips Feb/Apr/Jun/Sep/Nov** (Jan31→Mar31, Mar31→May31); last-day handles leap (Feb 2024 = 29th) vs non-leap (Feb 2025 = 28th); Dec→Jan year rollover; crashing job survives and advances; multiple due jobs all fire.
- **Subtasks** (3): `_02` all four `target_in_month/3` clauses (pure calendar math); `_03` `walk_months/5` (recursion + budget guard); `_04` `compute_next_run/2` (entry, budget=60).
- **Notable**: motivation is patterns cron can't express ("first Monday", "last weekday"). Uses `Calendar.ISO.days_in_month/2` and `Date.day_of_week/1` (ISO Mon=1) — no minute scan. Test anchor `~N[2025-01-01 00:00:00]` is a Wednesday.

Relevant paths (all under `/home/car/projects/elixir-sft-dataset/tasks/`): `004_001_job_scheduler_with_cron_like_expressions_01..05`, `004_002_intervalscheduler_01..03`, `004_003_retryscheduler_01..04`, `004_004_calendarscheduler_01..04`.

## Group 005 — Pub/Sub Event Buses

Four independent in-process pub/sub GenServer implementations, each a variation on "subscribers register interest, publishers fan out `{:event, ...}` messages." All are single-file, OTP-stdlib-only, use `Process.monitor` for automatic dead-subscriber cleanup on `:DOWN`, register subscriptions by the monitor `ref` (which doubles as the subscription id), support the same pid subscribing multiple times (one delivery per subscription), and accept a `:name` option for process registration. They diverge on the routing axis: 001 = topic wildcards; 002 = priority-ordered serial+cancellable delivery; 003 = bounded per-topic replay history; 004 = content-based filter DSL. Only 003 injects a clock for determinism. Directory scheme here: the second number (001–004) selects the distinct task family; the trailing `_NN` is the subtask (`_01` = full solution + `test_harness.exs`; `_02+` = fill-in-the-middle, single-function `solution.ex` with the module embedded in `prompt.md` and target replaced by `# TODO`).

### 005_001_pubsub_event_bus — Wildcard Pub/Sub with Monitor Cleanup
- **Interface**: `start_link(opts)` (`:name`); `subscribe(server, topic, pid) :: {:ok, ref}` (monitors pid, ref=monitor ref); `unsubscribe(server, topic, ref) :: :ok`; `publish(server, topic, event) :: :ok` (sends `{:event, topic, event}`). All client calls are `GenServer.call`.
- **Approach**: GenServer, three-index state `%{topics: %{pattern => %{ref => pid}}, refs: %{ref => {pid, topic}}, pids: %{pid => MapSet.t(ref)}}`. Wildcard match via `topic_matches?/2`: split both on `"."`, require equal segment count, then recursive `segments_match?/2` where `"*"` matches any one segment, literal segment must be equal. Publish iterates all patterns, `send/2` to each matching sub. `:DOWN` handler removes all of the pid's refs across topics and `Process.demonitor(r, [:flush])` the *other* refs (the fired one auto-cleans).
- **Key invariants tested**: `"orders.*"` matches exactly-one segment (not zero `"orders"`, not two `"orders.items.created"`); `"*.*"` = any two-segment; mid-pattern wildcard `"orders.*.completed"`; exact subscription never acts as wildcard; duplicate subscribe → event received twice; unsubscribing one ref leaves sibling on same topic; dead subscriber (single + multi-topic) fully cleaned; each subscribe returns unique ref; publish to empty topic is no-op; named registration works. Tests use `:sys.get_state(bus)` to sync after `:DOWN`.
- **Variations**: none (single problem family).
- **Subtasks**: 4 fill-in-the-middle — `_02` = `topic_matches?/2`; `_03` = `segments_match?/2` clauses; `_04` = `drop_subscription_entry/3`; `_05` = `clean_pid_refs/3`.
- **Notable**: monitor ref *is* the subscription identifier; wildcards only in subscriptions, never in published topic; only family with wildcard routing.

### 005_002_priorityeventbus — Priority-Ordered Serial Cancellable Delivery
- **Interface**: `start_link(opts)` (`:name`, `:delivery_timeout_ms` default `5_000`); `subscribe(server, topic, pid, priority)` (integer priority, higher=earlier) `:: {:ok, ref}`; `unsubscribe/3 :: :ok`; `publish(server, topic, event) :: {:ok, delivered_count}` (called with `:infinity` timeout); `subscribers(server, topic) :: [{ref, pid, priority}]` (desc priority, then sub-order); `ack({bus_pid, unique_ref}) :: :ok` / `cancel({bus_pid, unique_ref}) :: :ok` (subscriber-side helpers that `send` `{:ack,ref}`/`{:cancel,ref}` to bus).
- **Approach**: GenServer, state `%{topics: %{topic => [sub]}, monitors: %{ref => {pid, [topic]}}, next_seq, delivery_timeout_ms}`, sub = `%{ref, pid, priority, seq}`. Kept sorted by `insert_sorted` = `Enum.sort_by({-priority, seq})`. Exact topic match only (no wildcards). Core is `deliver_serially/5`: for each sub in order, `make_ref()`, `send(pid, {:event, topic, event, {self(), unique_ref}})`, then blocking `receive` for `{:ack, ^ref}` (continue, +1), `{:cancel, ^ref}` (stop, count current +1 but skip rest), matching `:DOWN` (treat as ack, `send(self(), down)` to re-queue for normal cleanup, continue), or `after timeout` (treat as ack, continue). This blocks the GenServer for the whole publish — intentional serialization.
- **Key invariants tested**: delivery strictly descending priority regardless of subscribe order; ties by subscription order; high-priority `:cancel` suppresses all lower (delivered_count excludes skipped); `:ignore` policy subscriber times out (~200ms) and counts as ack without cancelling downstream; `"*"`/`"orders.*"` treated as literal strings (no wildcard); multi-sub per pid independently unsubscribable; `:DOWN` removes across topics. Test uses a `ScriptedSub` GenServer with `:ack`/`:cancel`/`{:sleep,ms,then}`/`:ignore` policies.
- **Variations**: none.
- **Subtasks**: 3 fill-in-the-middle — `_02` = `deliver_serially/5` (the ack/cancel/timeout loop); `_03` = `handle_call({:subscribe,...})`; `_04` = `remove_ref_from_topic/3`.
- **Notable**: reply_to is `{bus_pid, make_ref()}` (distinct from the monitor ref); handler runs in subscriber's own process via send+receive, never `GenServer.call` on subscriber; publish serializes all bus traffic behind it.

### 005_003_replayeventbus — Bounded Per-Topic Replay History
- **Interface**: `start_link(opts)` (`:name`, `:default_history_size`=100, `:history_ttl_ms`=3_600_000, `:clock`=`fn -> System.monotonic_time(:millisecond) end`, `:cleanup_interval_ms`=60_000 or `:infinity` to disable); `subscribe(server, topic, pid, opts \\ [])` where `opts[:replay]` ∈ `:none` (default) | `:all` | positive-int `n`, `:: {:ok, ref}`; `unsubscribe/3`; `publish(server, topic, event) :: :ok`; `history(server, topic) :: [event]` (oldest→newest, TTL-applied); `set_history_size(server, topic, size)` (non-neg int, 0 disables/drops).
- **Approach**: GenServer, state `%{topics: %{topic => %{history: [{ts,event}], history_size, subs: [%{ref,pid}]}}, monitors, clock, default_history_size, history_ttl_ms, cleanup_interval_ms}`. History oldest-first; count bound via `Enum.take(-size)`, TTL via `evict_expired` = `Enum.drop_while(ts < now-ttl)`. **Replay-then-register atomicity**: subscribe handler runs inside one `GenServer.call` — snapshot history (post-TTL), `replay_events` sends selected events (`Enum.take(-n)` for int, all for `:all`) via `send/2` in order, *then* appends sub to topic — so an in-flight publish is either in history (seen in replay) or delivered live after registration, never missed/dup'd. Live and replay messages are indistinguishable (`{:event, topic, event}`). Periodic `:cleanup` (`Process.send_after`) evicts expired across topics and drops topics with empty history AND zero subs.
- **Key invariants tested**: default no-replay; `:all` and `:N` (with N>history → all) replay in order; replay precedes live; count bound (keeps last 10 of 15); `set_history_size` override + 0-disable; TTL eviction on replay/`history`; atomic no-miss-no-dup; `:DOWN` removes subs but preserves history; unsubscribe stops live but history keeps both; N subs per pid → N copies; cleanup evicts + drops empty-no-sub topics but keeps subbed topics with empty history.
- **Variations**: none.
- **Subtasks**: none (only `_01`).
- **Notable**: only family with injected `:clock` (test uses an `Agent`-backed `Clock` with `advance/set`) and `:cleanup_interval_ms: :infinity` for determinism; history is per-topic not per-subscriber.

### 005_004_filteredeventbus — Content-Based Filter DSL Routing
- **Interface**: `start_link(opts)` (`:name`); `subscribe(server, topic, pid, filter \\ [])` `:: {:ok, ref} | {:error, :invalid_filter}` (validates before calling GenServer); `unsubscribe/3`; `publish(server, topic, event) :: {:ok, matched_count}`; `test_filter(filter, event) :: boolean | {:error, :invalid_filter}` (pure, no GenServer).
- **Approach**: GenServer, state `%{topics: %{topic => [%{ref,pid,filter}]}, monitors}`. Exact topic match only. Filter = list of clauses, implicit AND (empty=always match). Clauses: `{:eq|:neq, path, v}`, `{:gt|:lt|:gte|:lte, path, v}` (numeric via `num_cmp` returning false if either operand non-number/nil), `{:in, path, list}`, `{:exists, path}` (non-nil), `{:any, [clauses]}` (OR), `{:none, [clauses]}` (NOT-OR). `path` = list of map keys / integer list indices navigated by `fetch/2` (`Map.fetch` for maps, `Enum.at(idx, :__missing__)` for lists, unresolved → `nil`, never raises). Two-phase: `valid_filter?`/`valid_clause?`/`valid_path?` structural validation (path elems must be atom/binary/integer; `:any`/`:none` need non-empty valid sub-lists) then `eval_filter`/`eval_clause`. `:DOWN` removes subs across topics.
- **Key invariants tested**: empty filter matches all; nested `:eq` path; `:neq`; numeric ops reject non-numeric/missing; `:in`; `:exists` (nil ≠ present); top-level AND; `:any` OR; `:none` exclusion; AND+nested `:any`; deep missing path → no crash/no match; integer list index `[:items, 0]`; invalid filters rejected (`:unknown_op`, non-list path, `{:any, []}`, float path elem `[3.14]`); `test_filter` pure booleans + same validation; multi-sub per pid → one delivery per matching sub; `matched_count` accuracy.
- **Variations**: none.
- **Subtasks**: none (only `_01`).
- **Notable**: DSL is data-only (no `eval`/no anon-fn stored in state) so state stays serializable; validation is purely structural and never evaluates; replaces wildcards entirely with content routing.

Reference files: `/home/car/projects/elixir-sft-dataset/tasks/005_001_pubsub_event_bus_01/{prompt.md,solution.ex,test_harness.exs}`, `/home/car/projects/elixir-sft-dataset/tasks/005_002_priorityeventbus_01/*`, `/home/car/projects/elixir-sft-dataset/tasks/005_003_replayeventbus_01/*`, `/home/car/projects/elixir-sft-dataset/tasks/005_004_filteredeventbus_01/*`.

## Group 006 — Caches

Four self-contained single-shot tasks (all `_01`; no variations, no fill-in-the-middle subtasks), each a single-file GenServer cache module using only OTP stdlib (no external deps). The common thread: an **injectable `:clock`** (zero-arity fn, default `System.monotonic_time(:millisecond)` — except LRU defaults to bare `System.monotonic_time/0`) makes time deterministic in tests; every ExUnit harness defines an Agent-backed fake `Clock` (`now/advance/set`, LRU's variant auto-increments on each `now`). Modules progress in sophistication: plain TTL → count-bounded LRU → proactive refresh-ahead → two-tier stale-while-revalidate. The three async caches (003, 004) share nearly identical `Task.start_link` + `make_ref()` in-flight-token machinery for discarding stale background results, and use `:sys.get_state/1` as a synchronization barrier in tests.

### 006_001_ttl_cache_with_lazy_expiration — TTL Cache with Lazy Expiration
- **Interface**: `start_link(opts)` (opts `:name`, `:clock`, `:sweep_interval_ms` default `60_000`); `put(server, key, value, ttl_ms) :: :ok`; `get(server, key) :: {:ok, value} | :miss`; `delete(server, key) :: :ok`.
- **Approach**: `GenServer`, `defstruct [:clock, :sweep_interval_ms, entries: %{}]`. Entry = `%{value, expires_at}` where `expires_at = clock.() + ttl_ms`. All ops are `handle_call`. Lazy expiration: `get` computes `clock.() < expires_at`; if expired returns `:miss` AND `Map.delete`s the key. Periodic `:sweep` via `Process.send_after(self(), :sweep, interval)` that `Enum.reject`s entries with `now >= expires_at` then reschedules itself.
- **Key invariants tested**: `:miss` for never-set/expired; lazy deletion actually removes from `state.entries` (checked via `:sys.get_state`); hit at `age=499`, miss at `age=501` for ttl 500; `put` fully resets TTL to `now + new_ttl`; key independence (a vs b); very short (1ms) / very large (86_400_000ms) TTLs; manual `send(cache, :sweep)` clears 100 expired keys, preserves live ones.
- **Variations**: none.
- **Subtasks**: none.
- **Notable**: Tests pass `sweep_interval_ms: :infinity` to disable auto-sweep; helper `schedule_sweep/1` has a guard clause `when is_integer(interval_ms)` plus a catch-all returning `:ok`, so `:infinity` silently no-ops. Boundary uses strict `<` on read but `>=` in sweep (consistent: expired exactly at `expires_at`).

### 006_002_lrucache — LRU Cache (count-bounded)
- **Interface**: `start_link(opts)` (opts `:name`, **required** `:capacity` positive int, `:clock`); `put(server, key, value) :: :ok`; `get(server, key) :: {:ok, value} | :miss`; `delete(server, key) :: :ok`; `size(server) :: non_neg_integer`; `keys_by_recency(server) :: [key]` (MRU-first).
- **Approach**: `GenServer`, `defstruct [:clock, :capacity, entries: %{}]`. Entry = `%{value, access_ts}`. No TTL, no sweep, no `Process.send_after`. Both `put` (always) and `get`-on-hit refresh `access_ts = clock.()`. Eviction is intentionally **O(n)**: `evict_lru/1` uses `Enum.min_by(entries, & &1.access_ts)` and evicts exactly one entry only when inserting a NEW key at `map_size >= capacity`. `keys_by_recency` = `Enum.sort_by(..., :desc)`.
- **Key invariants tested**: `size` never exceeds capacity (insert 10 into cap-3 → size 3); `start_link` raises `ArgumentError` on capacity 0 or -1 (validated both in `start_link` and re-fetched in `init`); new put evicts oldest; `get` promotes to MRU changing which key is evicted next; `put` on existing key never evicts (count unchanged) but updates value+ts; a `:miss` get refreshes nothing; `delete` does NOT count as access and frees a slot; textbook LRU trace producing specific eviction order.
- **Variations**: none.
- **Subtasks**: none.
- **Notable**: Prompt explicitly forbids DLL/ordered-map optimization — O(n) `Enum.min_by` is the wanted design; tie-breaking on equal `access_ts` is "arbitrary, don't special-case." Test `Clock.now` uses `get_and_update` returning strictly-increasing values so ordering is deterministic.

### 006_003_refreshaheadcache — Refresh-Ahead Cache
- **Interface**: `start_link(opts)` (opts `:name`, `:clock`, `:sweep_interval_ms` default `60_000`/`:infinity`, `:refresh_threshold` float in `(0.0,1.0]` default `0.8`); `put(server, key, value, ttl_ms, loader)` (guarded `is_integer(ttl_ms) and ttl_ms>0 and is_function(loader,0)`) `:: :ok`; `get(server, key) :: {:ok, value} | :miss`; `delete(server, key) :: :ok`; `stats(server) :: %{entries, refreshes_in_flight}`.
- **Approach**: `GenServer`, `defstruct [:clock, :sweep_interval_ms, :refresh_threshold, entries: %{}, in_flight: %{}]`. Entry = `%{value, expires_at, ttl_ms, loader}` (stores loader + original ttl). `get`: hard-expiry (`now >= expires_at`) → lazy evict + `:miss`; else if `should_refresh?` (`age = now-(expires_at-ttl_ms); age >= threshold*ttl_ms`) AND not already `in_flight` → `spawn_refresh` and return current value; else return value. `spawn_refresh/2` = `make_ref()` + `Task.start_link` running `loader.()` in child, sends `{:refresh_complete, key, ref, val}` (or `{:refresh_failed, key, ref, reason}` via rescue/catch) to parent. `handle_info` applies result ONLY if entry exists AND `in_flight[key] == ^task_ref`, updating `expires_at = now + entry.ttl_ms` (preserves original TTL); otherwise discards.
- **Key invariants tested**: no loader call below threshold (`age 500 < 800`); one get past threshold returns OLD value + triggers exactly one loader call, next get sees new; refresh resets TTL to `now + original_ttl`; 10 rapid gets → exactly 1 in-flight (dedup); `delete` during in-flight discards result (via `Map.delete(in_flight)` so ref mismatches); `put` during in-flight clears in-flight so stale result can't clobber user value; failing loader leaves old value + clears in-flight; sweep removes hard-expired and prunes orphaned in-flight refs.
- **Variations**: none.
- **Subtasks**: none.
- **Notable**: `refresh_threshold` stored as `* 1.0` (float-normalized). Sweep filters `in_flight` to only keys surviving in `pruned`. Tests use Agent-backed `Loader` (`next_value/0` counts calls, `slow_next_value(ms)` sleeps to widen the in-flight window) and a `wait_for_idle/2` poller on `stats.refreshes_in_flight`.

### 006_004_swrcache — Stale-While-Revalidate Cache
- **Interface**: `start_link(opts)` (opts `:name`, `:clock`, `:sweep_interval_ms` default `60_000`/`:infinity`); `put(server, key, value, fresh_ms, stale_ms, loader)` (guarded: both positive ints, `is_function(loader,0)`) `:: :ok`; `get(server, key) :: {:ok, value, :fresh} | {:ok, value, :stale} | :miss`; `delete(server, key) :: :ok`; `stats(server) :: %{entries, revalidations_in_flight}`.
- **Approach**: `GenServer`, `defstruct [:clock, :sweep_interval_ms, entries: %{}, in_flight: %{}]`. Entry = `%{value, fresh_until, hard_expires_at, fresh_ms, stale_ms, loader}` where `fresh_until = now+fresh_ms`, `hard_expires_at = now+fresh_ms+stale_ms`. `get` three-way cond: `now >= hard_expires_at` → lazy evict + `:miss`; `now < fresh_until` → `{:ok, value, :fresh}` (no revalidation); else stale → `{:ok, value, :stale}` + `spawn_revalidate` if not in-flight. Same `make_ref()` + `Task.start_link` machinery as 003 (`{:revalidate_complete/failed, key, ref, ...}`); on complete, resets BOTH windows using entry's stored `fresh_ms`/`stale_ms`.
- **Key invariants tested**: exact three-way boundaries for `fresh_ms=1000, stale_ms=2000` (fresh `[0,1000)`, stale `[1000,3000)`, miss `>=3000`); stale read triggers exactly one revalidation, later read sees new value now-fresh; 10 concurrent stale reads → 1 in-flight; successful revalidation grants full fresh+stale budget; failed revalidation leaves entry stale so next read retries (test uses `:counters` to fail-then-succeed); `delete` and overwriting `put` invalidate in-flight so result is discarded; sweep removes only past-`hard_expires_at`, keeps stale-but-live.
- **Variations**: none.
- **Subtasks**: none.
- **Notable**: Distinguished from refresh-ahead by the explicit `:fresh`/`:stale` tag in the return and a stale tier bounded by its own `stale_ms` (not a fraction of TTL). `put` validation is guard-clause based, so bad windows raise `FunctionClauseError` (not `ArgumentError`). Test `Loader.slow_next_value/1` again used to hold the in-flight window open.

All files are absolute under `/home/car/projects/elixir-sft-dataset/tasks/006_00{1,2,3,4}_*/` with `prompt.md`, `solution.ex`, `test_harness.exs`.

## Group 007 — Streaming Statistics

Four independent `GenServer` modules that ingest numeric values into multiple named streams and answer online-statistics queries without storing unbounded history. Common thread: a `push`/query split, a `state.streams` map keyed by arbitrary `name` (streams fully independent), a "largest-period-ever-wins" memory bound (`max_period`/`max_window_size` grows, never shrinks), newest-first `values` lists, all math coerced to float via `x * 1.0`, and `{:error, :no_data}` before any push. Pure OTP stdlib, no external deps, no clock injection (nothing time-based — all windows are count-based). Each family has exactly one directory (`_01`, full single-shot WITH `test_harness.exs`); there are NO variation dirs (b=02+) and NO fill-in-the-middle subtasks (d=02+) in this cluster.

### 007_001_moving_average_calculator — Simple & Exponential Moving Average
- **Interface**: `start_link(opts)` (`:name` passthrough); `push(server, name, value) :: :ok`; `get(server, name, type, period) :: {:ok, float} | {:error, :no_data}` — guard `type in [:sma, :ema] and is_integer(period) and period > 0`.
- **Approach**: `GenServer.call` for both push and get. Per-stream map `%{values: [float] newest-first, max_period: int, total_count: int, ema: %{period => float}}`. SMA = `Enum.sum(Enum.take(values, period)) / length(window)` (cold-start uses all available). EMA multiplier `k = 2/(period+1)`, seeded with first value, applied over FULL history; maintained as one running accumulator per `(name, period)` — `push_value/2` updates every registered EMA accumulator (`ema_step/3`, `@compile {:inline}`). New EMA period bootstraps from current `values` buffer (`bootstrap_ema/2`, oldest-first via `Enum.reverse`).
- **Key invariants tested**: SMA cold-start = mean of all; SMA window slide drops old; EMA period-1 = latest value; EMA hand-calc (`[10,20,30]`,p3 → 22.5; `[1..5]`,p5 → 275/81); EMA over 5000 `sin` values matches iterative reduce (eps 1e-6); larger period grows buffer; `:sys.get_state` asserts SMA buffer ≤ 10 after 1000 pushes (bounded memory).
- **Variations**: none.
- **Subtasks**: none.
- **Notable**: Trimming deferred from `push_value` to `compute/3` (`trim_values` only when `period ≤ max_period`; when period grows, buffer left untouched). Subtle consequence: EMA "full history" bootstrap can only see the post-trim buffer, so bootstrap of a large new period after prior small-period trimming is lossy — tests never exercise this so it passes. Docstring documents the exact state layout and memory contract.

### 007_002_weightedmovingaverage — Weighted & Hull Moving Average
- **Interface**: `start_link(opts)`; `push(server, name, value)` (guard `is_number(value)`, so non-numeric raises `FunctionClauseError`); `get(server, name, type, period) :: {:ok, float} | {:error, :no_data | :insufficient_data}` — guard `type in [:wma, :hma]`.
- **Approach**: WMA = linear weights newest=N…oldest=1, denominator `N*(N+1)/2` (`compute_wma/2` via `Enum.with_index` reduce; cold-start adjusts N to available count). HMA(P): `wma1 = WMA(div(P,2))`, `wma2 = WMA(P)`, `raw = 2*wma1 - wma2`, `hma = WMA(raw_buffer, round(sqrt(P)))`. Per-stream `%{values, max_period, hma: %{period => %{raw_buffer: [float]}}}`. Each `push_value/2` recomputes `raw` for EVERY registered HMA period and prepends to its `raw_buffer` (bounded `round(sqrt(period))`). New HMA period bootstraps by replaying all history oldest→newest (`bootstrap_raw_buffer/3`, iterates `for i <- (total-1)..0//-1` computing raw over each `Enum.drop(values, i)` suffix).
- **Key invariants tested**: WMA full window `[10..50]`,p5 → 550/15; WMA(3) of last-N; cold-start weights `[3,2,1]`/6; HMA(4) full hand-derivation → 35/9; HMA insufficient (< period values) → `:insufficient_data`; HMA increments across pushes (h4 ≠ h5); bootstrap-from-history matches fresh server; `max_period` grows to 10 without truncation; `:sys.get_state` asserts `values` length == 3.
- **Variations**: none.
- **Subtasks**: none.
- **Notable**: `:no_data` when `values == []` (checked before insufficient); `:hma` with fewer than `period` values → `:insufficient_data` (whereas `:wma` cold-starts). Trim deferred until AFTER HMA bootstrap so history isn't lost. Push is O(distinct HMA periods × max_wma_period).

### 007_003_streamingpercentile — Sliding-Window Percentile / Quantile
- **Interface**: `start_link(opts)`; `push(server, name, value, window_size)` (guard `is_number(value) and is_integer(window_size) and window_size > 0` → raises `FunctionClauseError` otherwise); `percentile(server, name, q) :: {:ok, float} | {:error, :no_data | :invalid_quantile}`; `percentiles(server, name, [_|_]=q_list) :: {:ok, %{q => float}} | {:error, ...}` (batch, one sort); `window(server, name) :: {:ok, [float]} | {:error, :no_data}` (returns insertion order oldest→newest via `Enum.reverse`).
- **Approach**: Per-stream `%{values: [float] newest-first, max_window_size: int}`. `push/4`: `new_max = max(max_window_size, window_size)`, prepend then `Enum.take(new_max)`. Query: `Enum.sort` ascending once, then `quantile/2`. Quantile = Hyndman-Fan type 7 / NumPy `"linear"` / Excel `PERCENTILE.INC`: `rank = q*(N-1)`, `lo = trunc(rank)`, `hi = min(lo+1, N-1)`, interpolate `lo_val + (rank-lo)*(hi_val-lo_val)`; single-element window short-circuits. Quantile validation (`valid_quantile?`: `q>=0.0 and q<=1.0`) done in the CLIENT process before `GenServer.call`.
- **Key invariants tested**: q=0→min, q=1→max; odd median = middle; even median interpolates (`[10,20,30,40]` p50 → 25); p25 of 1..10 → 3.25, p95 → 9.55; batch p50/p95/p99 of 1..100 → 50.5/95.05/99.01; window bounded drops oldest; `max_window_size` grows and never shrinks (length reaches 8 then 9, `:sys.get_state` == 10); duplicates; invalid q → `:invalid_quantile` (no partial results in batch).
- **Variations**: none.
- **Subtasks**: none.
- **Notable**: Simplest module (no separate `handle` for growth — inline in push clause). `Enum.at/2` on a list makes quantile O(N) per index lookup; prompt explicitly declares O(N log N) sort-per-query is intended scope (no skip-list/order-stat tree). `percentile/3` accepts integer q too (`is_float(q) or is_integer(q)`).

### 007_004_cusumanomaly — CUSUM Change-Point Detection + Welford
- **Interface**: `start_link(opts)` — opts `:threshold` (default 5.0), `:slack` (0.5), `:warmup_samples` (10), `:epsilon` (1.0e-6), `:name`; `push(server, name, value) :: :ok | :warming_up | {:alert, :upward_shift | :downward_shift}` (guard `is_number`); `check(server, name) :: {:ok, %{mean, stddev, s_high, s_low, samples, status: :normal | :warming_up}} | {:error, :no_data}`; `reset(server, name) :: :ok` (no-op if stream absent).
- **Approach**: Global config in top-level state, per-stream `%{samples, mean, m2, s_high, s_low}`. Welford online mean/variance (`welford_update/2`; `welford_stddev` = `sqrt(m2/n)` population). On push: if `samples < warmup_samples` → Welford-only + `:warming_up`; else z-score against PRIOR mean/stddev `z = (value - mean) / max(stddev, epsilon)`, then `s_high = max(0, s_high + z - slack)`, `s_low = max(0, s_low - z - slack)`, then Welford update. `s_high >= threshold` → `{:alert, :upward_shift}` + full reset; else `s_low >= threshold` → `:downward_shift` + reset (upward checked first).
- **Key invariants tested**: < warmup → `:warming_up`; warmup-th push → `:normal`+`:ok`; Welford mean/stddev of classic `[2,4,4,4,5,5,7,9]` (stddev 2.0); stable 500-sample signal never alerts; sustained +10 jump → upward alert; sustained −8 → downward alert; post-alert state fully zeroed (`samples==0`, `status==:warming_up`); manual `reset/2`; reset on unknown stream stays `:no_data`; per-stream isolation; bad opts raise `ArgumentError` (`validate!` in `start_link`); non-numeric raises `FunctionClauseError`.
- **Variations**: none.
- **Subtasks**: none.
- **Notable**: Two behaviors DIVERGE from prompt yet pass tests: (1) alert doesn't produce a re-learning reset — it stores `alerted: true` (`alerted_stream/0`), and subsequent pushes are FROZEN returning `:warming_up` until explicit `reset` (prompt said reset-and-re-learn immediately). (2) Undocumented extra guard: when CUSUM-active but `welford_stddev < slack`, returns `:ok` and updates Welford only, skipping CUSUM (guards against false alerts on near-zero variance). Options parsed twice (once in `start_link` for `validate!`, again in `init`); only `start_link` validates. Push return type is bare `{:alert, dir}`, but `@spec`/prompt bullet phrasing both list it as `{:alert, :upward_shift}`.

## Group 008 — CRDTs

Four independent GenServer-based CRDT (Conflict-free Replicated Data Type) implementations, each a self-contained single-file module using only OTP stdlib (no deps). Every family follows an identical shape: a `use GenServer` module with `start_link(opts)` accepting `:name`, mutation/query ops via `GenServer.call`, plus a **state/2 + merge/2** pair for gossip-style replication. All merges are proven idempotent/commutative/associative by dedicated tests that spin up multiple processes, snapshot `state/1`, cross-merge, and assert convergence of both `members`/`value` and raw `state`. Timestamps/counters are caller-supplied or internally monotonic (no wall clock), keeping tests deterministic. The four are the canonical CRDT progression: PN-Counter → LWW-Element-Set → 2P-Set → OR-Set. All four families have only the `_01` single-shot dir (with `test_harness.exs`); no b=02+ variations and no d=02+ fill-in-the-middle subtasks exist.

### 008_001_distributed_counter_with_crdt_style_merge — PN-Counter (Distributed Counter)
- **Interface**: `Counter.start_link(opts)`; `increment(server, node_id, amount \\ 1) :: :ok`; `decrement(server, node_id, amount \\ 1) :: :ok`; `value(server) :: integer()`; `merge(server, remote_state) :: :ok`; `state(server) :: %{p: g_counter, n: g_counter}`.
- **Approach**: Two grow-only G-Counters as maps `p` (per-node increments) and `n` (per-node decrements). Value = `sum(p) - sum(n)`. Ops use `update_in(state, [:p, node_id], &((&1 || 0) + amount))`. Merge = per-node `max` via `Map.merge/3` fold on each of `p` and `n` independently.
- **Key invariants tested**: value can go negative; per-node accumulation; merge takes max (never lowers counts); absent remote decrement treated as 0; idempotent/commutative/associative; empty-merge no-op; 100-node and 1M-magnitude cases.
- **Variations**: none.
- **Subtasks**: none.
- **Notable**: `increment`/`decrement` validate amount client-side (before the call) via `validate_amount!/2`, raising `ArgumentError` on non-positive integers. `merge/2` guards on `%{p: p, n: n}` with `is_map` and re-raises `ArgumentError` for malformed remote state. `node_id` is any term.

### 008_002_lww_element_set_crdt — LWW-Element-Set (Last-Writer-Wins)
- **Interface**: `LWWSet.start_link(opts)`; `add(server, element, timestamp) :: :ok`; `remove(server, element, timestamp) :: :ok`; `member?(server, element) :: boolean`; `members(server) :: MapSet.t`; `merge(server, remote_state) :: :ok`; `state(server) :: %{adds: ts_map, removes: ts_map}`.
- **Approach**: Two maps `adds`/`removes` of `element => latest_timestamp`. add/remove keep `max(current, timestamp)` per element (`update_in` with nil→ts clause). Presence: `add_ts > remove_ts` (remove defaults to 0 if absent). Merge = per-element `max` of both maps via `Map.merge/3`.
- **Key invariants tested**: **remove-wins on tie** (`add_ts == remove_ts` ⇒ absent, strict `>`); remove-before-add (lower ts) doesn't block membership; re-add with higher ts restores; repeated add keeps max ts; merge doesn't lower ts; remote remove overrides local add; CRDT props; string elements; named registration.
- **Variations**: none.
- **Subtasks**: none.
- **Notable**: Timestamps are caller-supplied positive integers (`validate_timestamp!/2` raises `ArgumentError` otherwise) — no injected clock. `members` filters `adds` by `add_ts > Map.get(removes, elem, 0)` into a MapSet.

### 008_003_two_phase_set_crdt — 2P-Set (Two-Phase Set)
- **Interface**: `TwoPhaseSet.start_link(opts)`; `add(server, element) :: :ok`; `remove(server, element) :: :ok`; `member?(server, element) :: boolean`; `members(server) :: MapSet.t`; `merge(server, remote_state) :: :ok`; `state(server) :: %{added: MapSet, removed: MapSet}`.
- **Approach**: Two grow-only G-Sets (`MapSet`s) `added` and `removed` (tombstones). Present = `MapSet.difference(added, removed)` / `member? and not member?`. Merge = `MapSet.union` on each set independently. `merge/2` coerces incoming values with `MapSet.new/1`.
- **Key invariants tested**: **permanent removal** — re-adding a tombstoned element raises `ArgumentError` (`:tombstoned`); removing a non-member or already-removed element raises `ArgumentError` (`:not_a_member`); add of present element is no-op; tombstone stays in both `added` and `removed`; merge is grow-only (`MapSet.subset?` before⊆after); tombstone propagation makes locally-added element disappear post-merge and un-re-addable; CRDT props.
- **Variations**: none.
- **Subtasks**: none.
- **Notable**: Validation is server-side: `handle_call` returns `{:error, :tombstoned}`/`{:error, :not_a_member}` and the client API wrapper converts to `ArgumentError` with element-specific messages. No timestamps/tags — this is the "no causal metadata" tradeoff.

### 008_004_observed_remove_set_crdt — OR-Set (Observed-Remove / Add-Wins Set)
- **Interface**: `ORSet.start_link(opts)`; `add(server, element, node_id) :: :ok`; `remove(server, element) :: :ok`; `member?(server, element) :: boolean`; `members(server) :: MapSet.t`; `merge(server, remote_state) :: :ok`; `state(server) :: %{entries: %{element => MapSet.t(tag)}, tombstones: MapSet.t(tag), clock: %{node_id => counter}}` where `tag = {node_id, counter}`.
- **Approach**: Each `add` mints a unique tag `{node_id, counter}` from an internal per-node monotonic `clock` (`Map.get(clock, node_id, 0) + 1`); tag added to that element's MapSet in `entries`. `remove` moves **all** of an element's current tags into `tombstones` and deletes the element key from `entries`. Merge: union tombstones, union per-element tag sets across all element keys, then `MapSet.difference(merged_tags, merged_tombstones)` to drop tombstoned tags (empty ⇒ element key omitted), and per-node `max` on clocks.
- **Key invariants tested**: **add-wins on concurrent add/remove** — flagship test: after both nodes share `{:a,1}`, node_a re-adds (`{:a,2}`) while node_b removes (tombstones `{:a,1}`); post bidirectional merge `:x` survives because `{:a,2}` ∉ tombstones. Also: remove-then-readd generates fresh tag (multi-cycle); each add is a distinct tag even same node; clock increments per node; removing non-member raises `ArgumentError`; state after remove drops the entries key but keeps tombstone; CRDT props; empty-merge no-op.
- **Variations**: none.
- **Subtasks**: none.
- **Notable**: `remove` returns `{:error, :not_a_member}` server-side → `ArgumentError` at API. The remove handler has an unusual guard `{:ok, tags} when tags != %MapSet{}` plus a redundant inner `MapSet.size(tags) == 0` check. `merge/2` guards on `%{entries:, tombstones:, clock:}` with `is_map` on entries/clock and `MapSet.new(tombstones)` coercion. `node_id` any term; clock is the only stateful counter (determinism from insertion order, no wall clock).

## Groups 009 + 010 — Coalescing / Dedup & Stores

Eight self-contained single-shot tasks (all `_001_..._01`; no `b=02+` variations, no `d=02+` fill-in-the-middle subtasks exist in this cluster). Every task is a single-file `GenServer` using only OTP stdlib (no external deps). Group 009 is about **concurrency coordination per key** (deduplicate/coalesce/gate in-flight work, spawning `Task.start` so the GenServer never blocks, replying to many `GenServer.from()` refs at once). Group 010 is about **keyed stores with time-based expiration** (sessions, tokens, leases, quotas), all sharing an identical scaffold: an injectable `:clock` zero-arity fn (default `System.monotonic_time(:millisecond)`), lazy expiry-on-access, and a periodic `Process.send_after(self(), :cleanup, ...)` sweep. The two 010-style patterns to contrast are **sliding-window** (session, reset on access) vs **absolute** (token/lease/quota, never extended on read).

### 009_001 — Request Deduplicator / Coalescer (`Dedup`)
- **Interface**: `start_link(opts)` (`:name`); `execute(server, key, func)` where `func` is arity-0, calls `GenServer.call(server, {:execute, key, func}, :infinity)`.
- **Approach**: State is `%{key => [GenServer.from()]}` — key present iff a task is in flight; value is arrival-ordered wait list. First caller: `Task.start` runs `func` under `try/rescue`, sends `{:task_done, key, result}` to parent; caller registered as `[from]`. Concurrent same-key callers appended (`callers ++ [from]`), do NOT re-invoke `func`. On `handle_info({:task_done,...})`, `Map.pop` the list and `GenServer.reply` each with the same result, clearing the key.
- **Result normalisation**: `{:ok, v}`→as-is; `{:error, r}`→as-is; other `v`→`{:ok, v}`; raise→`{:error, {:exception, exception}}`.
- **Key invariants tested**: N concurrent same-key calls → `func` runs exactly once (Agent counter==1), all get same result; distinct keys run independently/concurrently (counter==5); key cleared after success AND after error so next call re-runs; error/exception broadcast to all waiters; GenServer stays responsive during a 500ms slow func (fast call <200ms); sequential same-key calls each re-execute.
- **Variations**: none. **Subtasks**: none.
- **Notable**: `Task.start` (fire-and-forget, not `Task.async`/monitored) — a crash outside `rescue` would silently leave the key stuck, but `func` errors are all caught by `rescue`. Only `rescue` (no `catch` for exits/throws).

### 009_002 — Write-Behind Batch Coalescer (`BatchCollector`)
- **Interface**: `start_link(opts)` (`:name`, **required** `:flush_interval_ms`); `submit(server, key, item, flush_fn, opts \\ [])` — `flush_fn` is arity-1 (receives item list in submission order), `opts[:max_batch_size]` default 10; `pending_count(server, key)` → integer.
- **Approach**: State `%{flush_interval_ms, batches: %{key => %{items, callers, flush_fn, max_batch_size, timer_ref}}}`. First `submit` for a key starts `Process.send_after(self(), {:flush_timer, key}, interval)` and buffers item; items/callers **prepended** (O(1)), reversed at flush for order. Flush triggers when `length(items) >= max_batch_size` OR the `:flush_timer` fires. `do_flush` pops the key (prevents new items joining a dying batch), cancels timer, spawns `Task.start` running `flush_fn` under `try/rescue`, sends `{:batch_done, callers, result}` → all replied.
- **Key invariants tested**: single item flushes on timer (~100ms measured); concurrent submitters batched (flush_fn once, all get `{:ok, 15}`); order preserved (sorted); `max_batch_size: 3` flushes before timer (<300ms); timer flush waits ~80-300ms; independent per-key batches/timers; error+exception broadcast; key cleared after flush/error; stale `:flush_timer` after threshold-flush harmlessly ignored (key `:error`).
- **Variations**: none. **Subtasks**: none.
- **Notable**: `max_batch_size <= 1` special-cased to flush immediately on first submit. Same `Task.start` + `{:ok,_}/{:error,_}/other` normalisation as 009_001.

### 009_003 — Retry-Aware Request Deduplicator (`RetryDedup`)
- **Interface**: `start_link(opts)` (`:name`); `execute(server, key, func, opts \\ [])` with `:max_retries` (default 3), `:base_delay_ms` (100), `:max_delay_ms` (5000); `status(server, key)` → `:idle | {:retrying, attempt, max_retries}` (attempt 1-based).
- **Approach**: Dedup (like 009_001) PLUS exponential backoff. State `%{key => %{callers, func, retry_config, attempt, status}}` (`attempt` 0=initial). `spawn_attempt` = `Task.start` → `{:task_result, key, result}`. On success → reply all, delete key. On `{:error,_}`: if `attempt < max_retries`, `Process.send_after(self(), {:retry_now, key}, delay)`, bump attempt, status `:waiting_retry`; else reply all with last error, delete key. `{:retry_now, key}` re-spawns same `func`. Delay = `min(base * 2^(attempt-1), max_delay_ms)` via `Integer.pow`.
- **Key invariants tested**: retries then succeeds (initial+2 = 3 calls); exhausted returns last error (initial+3 = 4 calls); exception retried & wrapped; callers arriving mid-retry-sequence share eventual result without restarting retries; `status` is `:idle` during attempt 0 (first run), `{:retrying, _, max}` once retrying, `:idle` after done; backoff delays monotonically increasing (~50/100/200); key cleared after final success/failure; responsiveness during retries.
- **Variations**: none. **Subtasks**: none.
- **Notable**: exceptions treated as `{:error, {:exception, e}}` for retry purposes (so raises ARE retried, unlike some designs). `status` deliberately reports `:idle` during the very first attempt (attempt==0).

### 009_004 — Per-Key Bounded Concurrency Pool (`KeyedPool`)
- **Interface**: `start_link(opts)` (`:name`, **required** `:max_concurrency` positive int — `start_link` raises `ArgumentError` otherwise); `execute(server, key, func)` (arity-0); `status(server, key)` → `%{running: n, queued: n}` (`%{running: 0, queued: 0}` for idle/unknown).
- **Approach**: NOT dedup — every caller's own `func` runs; pool only gates concurrency. State `%{max_concurrency, keys: %{key => %{running, queue: [{from, func}], tasks: %{ref => from}}}}`. If `running < max`, `start_task` (make_ref, `Task.start`, `{:task_done, key, ref, result}`); else append `{from, func}` to FIFO queue. On `:task_done`: `Map.pop` ref→reply that caller, decrement running, `maybe_start_next` dequeues head and starts it; key deleted from map when `running==0 and queue==[]`.
- **Key invariants tested**: each caller gets its OWN result (values `[1..5]`); all funcs run (counter==5, contrasted with dedup); peak concurrency ≤ max; FIFO order strict (`[:blocker,:first,:second,:third]`); independent keys run in parallel (~100ms not 300ms); `status` running/queued counts (2/2) then cleaned to zeros; crashed/erroring task still frees slot for next queued caller; `ArgumentError` on `max_concurrency: 0`/`-1`; stress 40 callers × 4 keys.
- **Variations**: none. **Subtasks**: none.
- **Notable**: uses `make_ref()` per task to map completion → caller. `Task.start` (unmonitored) but result always captured via `try/rescue`, so a "crash" is really a caught exception that still sends `:task_done`.

### 010_001 — Session Store w/ Inactivity Timeout (`SessionStore`)
- **Interface**: `start_link(opts)` (`:name`, `:timeout_ms` default 1_800_000, `:cleanup_interval_ms` default 60_000, `:clock`); `create(server, data)`→`{:ok, session_id}`; `get`→`{:ok, data}|{:error, :not_found}` (**resets timer**); `update(server, id, new_data)`→`{:ok, new_data}|{:error,:not_found}` (**resets timer**); `touch`→`:ok|{:error,:not_found}` (**resets timer**); `destroy`→`:ok` always.
- **Approach**: **Sliding window**. State `%{sessions: %{id => %{data, last_active}}, timeout_ms, cleanup_interval_ms, clock}`. Every read/update/touch sets `last_active = now`. `expired?` = `now - last_active >= timeout_ms`. `fetch_live_session` returns `{:ok,_}|:expired|:missing`; `:expired` deletes lazily. Periodic `:cleanup` uses `Map.filter` to drop expired. IDs: `:crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)` (~22 chars).
- **Key invariants tested**: sliding reset via get/touch/update keeps alive across 5×800ms cycles; expiry at ≥timeout (999 alive, 1001 dead); session independence; destroy idempotent & isolated; sweep empties 100 expired but keeps active; various data types; 1ms-timeout edge.
- **Variations**: none. **Subtasks**: none.
- **Notable**: `@default_clock &__MODULE__.__default_clock__/0` public wrapper (comment: avoids capturing a private fn in some compile contexts). Tests inject a fake `Clock` Agent (`now/advance/set`) and use `cleanup_interval_ms: :infinity` (`schedule_cleanup` guards on `is_integer`, no-ops for `:infinity`). Cleanup driven manually via `send(store, :cleanup)` + `:sys.get_state/1` sync.

### 010_002 — One-Time Token Store w/ Absolute Expiration (`OneTimeTokenStore`)
- **Interface**: `start_link(opts)` (`:name`, `:default_ttl_ms` default 3_600_000, `:cleanup_interval_ms`, `:clock`); `mint(server, payload, opts \\ [])` (`opts[:ttl_ms]` override)→`{:ok, token_id}`; `verify`→`{:ok, payload}|{:error,:not_found}` (**non-destructive, does NOT extend**); `redeem`→`{:ok, payload}|{:error,:not_found}` (consumes/deletes, single-use); `revoke`→`:ok` always; `active_count(server)`→count of non-expired tokens.
- **Approach**: **Absolute deadline** `expires_at = now + ttl_ms` at mint, never touched on access (contrast 010_001). State `%{tokens: %{id => %{payload, expires_at}}, ...}`. `expired?` = `now >= expires_at`. `verify` reads without deleting live tokens (but deletes on `:expired`); `redeem` deletes on success; `revoke` unconditional delete; `active_count` = `Enum.count(not expired?)`.
- **Key invariants tested**: verify non-consuming (repeatable); redeem consumes (2nd redeem fails); verify fails post-redeem/revoke; **verify does NOT extend** (verify at 800ms then expired at 1100ms — explicitly the sliding-vs-absolute discriminator); per-token `:ttl_ms` override; independence; `active_count` reflects redeem+expiry; sweep; 1ms TTL; double-redeem & revoke-then-redeem rejected.
- **Variations**: none. **Subtasks**: none.
- **Notable**: Structurally near-identical scaffold to 010_001 but `>=` absolute semantics and adds `active_count`. Same clock/cleanup test harness pattern.

### 010_003 — Exclusive Lease Manager w/ Ownership (`LeaseManager`)
- **Interface**: `start_link(opts)` (`:name`, `:lease_duration_ms` default 30_000, `:cleanup_interval_ms`, `:clock`); `acquire(server, resource, owner)`→`{:ok, lease_id}|{:error, :already_held, current_owner}`; `release(server, resource, owner)`→`:ok|{:error, :not_held}`; `renew(server, resource, owner)`→`{:ok, new_expires_at}|{:error,:not_held}`; `holder(server, resource)`→`{:ok, owner, expires_at}|{:error, :available}`; `force_release(server, resource)`→`:ok` always (admin).
- **Approach**: Mutual-exclusion primitive: at most one live lease per resource. State `%{leases: %{resource => %{lease_id, owner, expires_at}}, ...}`. `acquire` grants only if `:expired`/`:missing`; a live lease → `{:error, :already_held, lease.owner}` (**NOT idempotent** — same owner re-acquire also errors). `release`/`renew` guarded by `when lease.owner == owner`; wrong owner → `{:error, :not_held}`; expired → delete + `:not_held`. `renew` sets `expires_at = now + duration`. `holder` returns owner+expiry or `:available`.
- **Key invariants tested**: acquire grants; second/same owner both get `:already_held` w/ current owner; release only by owner (wrong owner `:not_held`), re-acquire after release; holder returns exact `expires_at==1000`; expiry frees for other owner; release/renew of expired → `:not_held`; renew extends from now (800→1800), repeated renews keep alive; force_release ignores owner; resource independence; arbitrary term resources/owners; sweep.
- **Variations**: none. **Subtasks**: none.
- **Notable**: The distinguishing feature vs other stores is **ownership-guarded mutation** (`when lease.owner == owner` guards) and the 3-tuple `{:error, :already_held, owner}` return. Same clock/cleanup harness.

### 010_004 — Rolling-Window Quota Tracker (`QuotaTracker`)
- **Interface**: `start_link(opts)` (`:name`, `:max_window_ms` default 3_600_000, `:cleanup_interval_ms`, `:clock`); `record(server, key, amount, quota, window_ms)`→`{:ok, remaining}|{:error, :quota_exceeded, overage}` (**all-or-nothing**, rejected recordings NOT stored); `remaining(server, key, quota, window_ms)`→`{:ok, remaining}` (read-only, evicts, `max(_,0)`); `usage(server, key, window_ms)`→`{:ok, total}`; `reset(server, key)`→`:ok`; `keys(server)`→`[key]` (all keys w/ any entries, NOT window-filtered).
- **Approach**: Per-key list of `%{amount, recorded_at}` timestamped entries (prepended). Two eviction windows: per-call `window_ms` (for the usage math) and store-level `max_window_ms` (for what's retained/leaked). `evict_expired` keeps `recorded_at > now - window_ms`. `record`: compute `current_usage` over `window_ms`; if `current_usage + amount > quota` → reject with `overage = current_usage + amount - quota`, but still retain (via max_window) without adding; else prepend new entry, `remaining = quota - (current_usage + amount)`. Sweep maps each key through `evict_expired(..., max_window_ms)` and rejects now-empty keys.
- **Key invariants tested**: record returns remaining; accumulation (3 then 5 of 10 → remaining 2); exceed rejected w/ exact overage (1), rejected doesn't consume; unknown key → full quota / 0 usage; entries expire after window; expired usage frees quota; partial expiry (t=0 drops, t=500 kept); reset clears; independence; `keys` sorted; exact boundary (record 10 of 10 → remaining 0), 1-over fails; `record` amount 0 succeeds w/o effect; **same key with different `window_ms` gives different visible usage** (1000ms→3, 2000ms→8); sweep drops fully-expired keys but keeps active.
- **Variations**: none. **Subtasks**: none.
- **Notable**: The only 010 store with a **quantity/quota** dimension rather than presence/expiry, and the only one where the query-time `window_ms` is a per-call parameter decoupled from the retention `max_window_ms`. Boundary is strict `>` on `recorded_at > cutoff` (entry at exactly `now - window_ms` is evicted). Same fake-Clock + manual `:cleanup` harness as the rest of 010.

Cross-cluster notes for a newcomer: all 8 tests use `use ExUnit.Case, async: false`; 009 tests rely on real `Process.sleep`/`:timer.tc` timing + `Agent` counters, whereas 010 tests are fully deterministic via an injected `Clock` Agent and `cleanup_interval_ms: :infinity` with manual `send(pid, :cleanup)` + `:sys.get_state/1`. Every 010 module shares the identical `@default_clock &__MODULE__.__default_clock__/0` idiom, `schedule_cleanup/1` with an `is_integer` guard, a `fetch_live_*` `{:ok,_}|:expired|:missing` helper, lazy delete-on-expired-access, and a `handle_info(msg, state)` catch-all that `Logger.warning`s. All 009 modules share `Task.start` + `try/rescue` normalisation (`{:ok,_}`/`{:error,_}`/other→`{:ok,other}`/raise→`{:error,{:exception,e}}`) and reply-to-many-`from`s via `handle_info` result messages.

## Groups 011 + 012 — Worker Pools & Event-Sourced Aggregates

Two thematic clusters of self-contained OTP exercises. **011** = four incremental variants of a GenServer-managed worker pool (bounded FIFO queue → priority+starvation → cancellation → per-task timeout+retry), each built on a `DynamicSupervisor` of `:temporary` worker GenServers, `Process.monitor` for crash detection, and a client-side `await/3` that is a *bare mailbox `receive`* (the pool `send`s results directly to the caller pid, so the `pool` arg to `await` is ignored). **012** = four isomorphic event-sourced aggregate GenServers (bank account, subscription, inventory, task tracker) sharing one skeleton: a `store = %{id => %{state, events}}` map, `validate_command → apply_event → append`, independent per-id state, plain-map events with a `:type` key. No clock is injected anywhere — pool timing tests use real `Process.sleep` and `System.monotonic_time(:millisecond)`; aggregates are purely synchronous/deterministic. All eight dirs are `_01` single-shot tasks (full three-file set); no `b=02+` variations and no `d=02+` fill-in-the-middle subtasks exist in this cluster (the `b` field here indexes distinct families, not variations). No external deps.

Shared pool mechanics (apply to all 011 families): `start_link/1` accepts `:pool_size` (default 3), `:max_queue` (default 10), `:name`; workers spawned in `init` via `DynamicSupervisor.start_child(sup, {…Worker, [self()]})` and each `Process.monitor`ed (`monitors: %{mref => pid}`); dispatch is instant to an idle worker else enqueue (`:queue`) else `{:error, :queue_full}`; worker runs `func.()` *synchronously inside `handle_info({:run, …})`* and `send`s `{:task_finished, self(), ref, result}` back; a `func` that raises crashes the worker → `{:DOWN, …}` → client notified + replacement worker started + `dispatch_next` immediately re-fills it from the queue. `submit` returns `{:ok, ref}` with `ref = make_ref()`.

### 011_001_bounded_mailbox_worker_pool — Bounded-Mailbox Worker Pool
- **Interface**: `start_link(opts)`; `submit(pool, task_func)` (0-arity fn) → `{:ok, ref}` | `{:error, :queue_full}`; `await(pool, ref, timeout \\ 5_000)` → `{:ok, result}` | `{:error, :timeout}` | `{:error, {:task_crashed, reason}}`; `status(pool)` → `%{busy_workers, idle_workers, queue_length}`.
- **Approach**: single `GenServer` (`WorkerPool`) + inner `WorkerPool.Worker` (`use GenServer, restart: :temporary`). `State` struct: `queue: :queue.new()`, `idle_workers: [pid]`, `busy_workers: %{pid => {ref, client_pid}}`, `monitors: %{mref => pid}`. FIFO via Erlang `:queue`. `handle_call({:submit,…}, {from_pid,_}, …)` uses `cond`: idle→dispatch, `:queue.len < max_queue`→enqueue, else reject.
- **Key invariants tested**: FIFO order (release workers one at a time, assert `{:executed, i}` in order); queue rejects the overflow submit; `status` counts accurate; crash returns `{:error, {:task_crashed, _}}` and awaiter of queued task behind a crash still gets `{:ok, :survived}`; worker count restored to `pool_size` after crash; `pool_size: 1` and `max_queue: 0` (busy → immediate reject) edge cases; unknown/`make_ref()` await → `{:error, :timeout}`.
- **Variations**: none present. **Subtasks**: none present.
- **Notable**: DOWN handler distinguishes busy (`Map.pop(busy_workers, pid)`) vs idle worker death; awaiter decoupled from server (client-side `receive` on `{^ref, :result|:error, …}`).

### 011_002_priority_worker_pool_with_starvation_prevention — Priority Pool w/ Starvation Prevention
- **Interface**: adds `:promote_after_ms` (default 5_000) to `start_link`; `submit(pool, task_func, priority \\ :normal)` with `priority in [:high, :normal, :low]` (guard `priority in @priorities`); `status` → `%{busy_workers, idle_workers, queue_high, queue_normal, queue_low, total_queue_length}`.
- **Approach**: `State.queues = %{high:, normal:, low:} ` (each a `:queue`); tasks stored as `{ref, client_pid, func, enqueued_at}` where `enqueued_at = System.monotonic_time(:millisecond)`. `dequeue_highest/1` scans `[:high, :normal, :low]` via `reduce_while`. `max_queue` bounds the *sum* (`total_queue_length`). Starvation: `schedule_promotion` = `Process.send_after(self(), :promote_stale_tasks, promote_after_ms)`; handler `partition_stale/3` splits each queue by `now - enqueued_at >= threshold`, promotes low→normal and normal→high (appended to *back* of target queue), reschedules.
- **Key invariants tested**: high dequeued before normal before low; FIFO within a level; per-priority `status` counts; queue-full rejects across all priorities; low task promoted after `promote_after_ms` (setup uses 500ms) runs before a later-submitted fresh normal.
- **Variations**: none present. **Subtasks**: none present.
- **Notable**: idle-worker dispatch ignores priority (nobody waiting); promotion loses intra-level age ordering (appends to back) but tests don't exercise that; only normal/high pumped by promotion each tick (a low task needs two ticks to reach high).

### 011_003_cancellable_worker_pool — Cancellable Worker Pool
- **Interface**: same as 001 plus `cancel(pool, ref)` → `:ok` | `{:error, :not_found}`; `await` adds `{:error, :cancelled}`; `status` adds `:cancelled_count` (cumulative). Module `CancellablePool`.
- **Approach**: `State` adds `pending_refs: %{ref => client_pid}` (tracks *queued* refs), `cancelled_refs: MapSet` (running refs killed via cancel, to distinguish from genuine crash in DOWN), `cancelled_count`. `handle_call({:cancel, ref},…)`: if in `pending_refs` → `queue_remove/2` (rebuild `:queue` minus ref) + send `{ref, :error, :cancelled}`; elif running (`find_busy_worker` by ref) → `Process.exit(worker, :kill)` + mark in `cancelled_refs` + send `:cancelled`; else `{:error, :not_found}`. DOWN handler checks `MapSet.member?(cancelled_refs, ref)` → skip the `task_crashed` message (already sent), just cleanup.
- **Key invariants tested**: cancel pending removes from queue + frees a slot; cancel running kills worker, notifies awaiter, replacement picks up next queued task; unknown/completed/double-cancel → `{:error, :not_found}`; `cancelled_count` increments per cancel; non-cancellation crash still yields `{:task_crashed, …}`.
- **Variations**: none present. **Subtasks**: none present.
- **Notable**: cancel uses `:kill` (untrappable) to preempt a running task; the `cancelled_refs` MapSet is the mechanism that prevents a cancel from being misreported as a crash.

### 011_004_worker_pool_with_per_task_timeouts_and_retry — Retry Pool w/ Per-Task Timeouts
- **Interface**: `submit(pool, task_func, opts \\ [])` with `:task_timeout` (default 30_000) and `:max_retries` (default 0, meaning no retries); `await` errors: `{:error, {:task_failed, reason, attempts}}` (retries exhausted on crash) and `{:error, {:task_timeout, attempts}}` (final attempt timed out); `status` adds `:retry_count`. Module `RetryPool`.
- **Approach**: per-task `%TaskInfo{ref, client_pid, func, task_timeout, max_retries, attempts: 0}` stored as the busy value (`busy_workers: %{pid => %TaskInfo{}}`). `dispatch_to_worker/3` increments `attempts`, sends `{:run,…}`, and arms `Process.send_after(self(), {:task_timeout, worker}, task_timeout)`; timer bookkeeping in `timers: %{tref => pid}` + `worker_timers: %{pid => tref}` (`cancel_task_timer/2` on completion). On `:task_timeout` → `Process.exit(worker, :kill)` and stash `{:timed_out, task_info}` in `busy_workers` so the ensuing `:DOWN` is classified as timeout vs crash. `handle_task_failure/3`: if `attempts <= max_retries` re-enqueue at **front** via `:queue.in_r` + bump `retry_count`; else send terminal error. Retried tasks jump the queue front; new submissions are FIFO.
- **Key invariants tested**: crash w/ `max_retries: 0` → `{:task_failed, _, 1}`; flaky task (Agent counter) succeeds after N failures with exact total-attempt count; timeout w/o retries → `{:task_timeout, 1}`; timeout then retry succeeds; timeout exhausting retries → `{:task_timeout, 2}`; `retry_count` equals number of failed attempts; `await` short timeout fires even while task is mid-retry.
- **Variations**: none present. **Subtasks**: none present.
- **Notable**: `attempts` incremented at dispatch (so count is 1-based on first run); test harness introduces `flaky_task/3` built on an `Agent` counter; `{:timed_out, task_info}` tuple in `busy_workers` is the timeout-vs-crash discriminator (mirrors 003's `cancelled_refs` trick).

### 012_001_event_sourced_aggregate — Bank Account Event-Sourced Aggregate
- **Interface** (`Aggregate`): `start_link(opts)` (`:name`, seeds state `%{}`); `execute(server, id, command)` → `{:ok, [event]}` | `{:error, reason}`; `state(server, id)` → `%{name, balance, status: :open}` | `nil`; `events(server, id)` → oldest-first list. Commands: `{:open, name}`, `{:deposit, amount}`, `{:withdraw, amount}`.
- **Approach**: `GenServer` state = `store :: %{id => %{state, events}}`. `handle_call({:execute,…})`: `validate_command(current.state, cmd)` → events, `Enum.reduce(events, state, &apply_event/2)`, `events ++ new_events` (O(n) append). `get_state` via `get_in(store, [id, :state])`. Events: `%{type: :account_opened, name}`, `:amount_deposited`/`:amount_withdrawn` w/ `:amount`. `apply_event(:account_opened, _nil)` builds `%{name, balance: 0, status: :open}`.
- **Key invariants tested**: open twice → `:already_open`; deposit/withdraw before open → `:account_not_open`; non-positive amount → `:invalid_amount`; over-withdraw → `:insufficient_balance` (balance unchanged); exact-balance withdraw → 0; failed commands append no events; per-id independence (`"acct:1"` vs `"acct:2"`); `state`/`events` for unknown id → `nil`/`[]`; a 7-command replay asserts final balance 0 and exact 6-event `:type` sequence.
- **Variations**: none present. **Subtasks**: none present.
- **Notable**: canonical template the other three 012 families clone verbatim (same store shape, same execute/state/events plumbing).

### 012_002_subscription_lifecycle_event_sourced_aggregate — Subscription Lifecycle Aggregate
- **Interface** (`SubscriptionAggregate`): commands `{:create, plan_name}`, `{:activate}`, `{:suspend, reason}`, `{:cancel}`, `{:reactivate}`; state `%{plan, status, reason}` | `nil`; status FSM `pending → active → suspended → cancelled → (reactivate) active`.
- **Approach**: same store/execute skeleton; `validate_command` pattern-matches on `%{status: …}`. Events `:subscription_created|_activated|_suspended|_cancelled|_reactivated`. `apply_event` transitions status and sets/clears `:reason` (suspend stores reason, cancel/reactivate reset it to `nil`).
- **Key invariants tested**: create-twice → `:already_exists`; any command pre-create → `:not_found`; activate when not pending → `:not_pending`; suspend when not active → `:not_active`; cancel-when-cancelled → `:already_cancelled`; reactivate when not cancelled → `:not_cancelled`; cancel from suspended succeeds; 7-command replay asserts final `:cancelled`/`reason: nil` and exact event sequence.
- **Variations**: none present. **Subtasks**: none present.
- **Notable**: solution adds a rule the prompt never specifies — `validate_command(%{status: :pending}, {:cancel})` returns `{:error, :not_active}` (prompt only mandated `:already_cancelled` for cancel); untested by the harness but a divergence to be aware of.

### 012_003_inventory_stock_event_sourced_aggregate — Inventory Stock Aggregate
- **Interface** (`InventoryAggregate`): commands `{:register, name, sku}`, `{:receive_stock, qty}`, `{:ship_stock, qty}`, `{:adjust, qty}`; state `%{name, sku, quantity_on_hand, status: :registered}` | `nil`.
- **Approach**: identical skeleton; events `:product_registered` (carries `name`+`sku`), `:stock_received`, `:stock_shipped`, `:stock_adjusted` (all carry `:quantity`). `apply_event` +/- `quantity_on_hand`.
- **Key invariants tested**: re-register → `:already_registered`; pre-register commands → `:not_registered`; non-positive receive/ship qty → `:invalid_quantity`; over-ship → `:insufficient_stock` (qty unchanged); `:adjust` allows negative but rejects **zero** (`:invalid_quantity`) and rejects a negative that would drive `quantity_on_hand` below 0 (`:insufficient_stock`); 7-command replay lands at 0 with exact 6-event sequence.
- **Variations**: none present. **Subtasks**: none present.
- **Notable**: `:adjust` is the only signed command — validation is `quantity == 0` and `state.quantity_on_hand + quantity < 0`.

### 012_004_task_tracker_event_sourced_aggregate — Task/Issue Tracker Aggregate
- **Interface** (`TaskAggregate`): commands `{:create, title, priority}` (`priority in [:low,:medium,:high]`, module attr `@valid_priorities`), `{:assign, assignee}`, `{:start}`, `{:complete}`, `{:reopen}`; state `%{title, assignee, status, priority}` | `nil`; status FSM `created → in_progress → completed → (reopen) created` with `assignee` reset to `nil` on create/reopen.
- **Approach**: same skeleton; events `:task_created` (title+priority), `:task_assigned` (assignee), `:task_started`, `:task_completed`, `:task_reopened`. `validate_command` clauses order matters (e.g. `%{assignee: nil}, {:start}` → `:not_assigned` before `%{status: :in_progress}` → `:already_started`).
- **Key invariants tested**: create-twice → `:already_exists`; bad priority (`:urgent`) → `:invalid_priority`; assign after complete → `:already_completed`; start without assignee → `:not_assigned`; start when in_progress → `:already_started`; complete when not in_progress → `:not_in_progress`; reopen when not completed → `:not_completed`; reopen resets to `:created` + `assignee: nil`; reassign allowed; 8-command replay asserts final assignee `"Diana"`/`:completed` and exact event sequence.
- **Variations**: none present. **Subtasks**: none present.
- **Notable**: test harness carries an explicit `# FIXED: Re-opening an in-progress task must return :not_completed` comment (line 220) — evidence of a previously-corrected bug where reopen from `:in_progress` misbehaved; the only 012 family with an enum-validated field (`priority`).

## Groups 013 + 014 + 015 — Retry Workers, Priority Queues, Monitors

Three families of stateful OTP `GenServer` components exercising async scheduling, deterministic time via an injected `:clock` function, and callback/notification hooks. All solutions are single-file, OTP-stdlib-only (no deps). Every family shares the same testing idiom: a fake `Clock` Agent (`now/advance/set`), injected `:random`/`:notify`/`processor`/`check_func` functions, and step-through synchronization (`send` + `assert_receive`, or a `drain`/`status` call to flush the mailbox). Each group has one original (`_001`) plus three sibling problem-variations (`_002/_003/_004`), all at subtask `_01` (full single-shot, each WITH its own `test_harness.exs`); there are NO fill-in-the-middle (`d=02+`) subtasks in this cluster. Directory layout is `a_b_c_d` where `b` is the variation index — so within each group the four dirs are genuinely different problems, not paraphrases.

### tasks/013_* — Retry Workers (exponential backoff family)
- **Interface (013_001 `RetryWorker`)**: `start_link(opts)` accepting `:clock` (0-arity ms, default `System.monotonic_time(:millisecond)`), `:random` (1-arity `max -> 0..max-1`, default `:rand.uniform(max)-1`), `:name`. `execute(server, func, opts) :: {:ok, any} | {:error, :max_retries_exceeded, last_reason}` where `func` is 0-arity returning `{:ok, r}`/`{:error, reason}`; opts `:max_retries`(3), `:base_delay_ms`(100), `:max_delay_ms`(10_000).
- **Approach**: `execute` is a blocking `GenServer.call(..., :infinity)`; server replies asynchronously via `GenServer.reply/2`. `handle_call` runs `func` synchronously in the GenServer, then either replies or schedules `Process.send_after(self(), {:retry, func, attempt, opts, from}, total_wait)`. Delay = `min(base_delay <<< min(n,50), max_delay)` (`import Bitwise`, `n = next_attempt-1`) plus `jitter = random.(delay)`; `total_wait = delay + jitter`. State is minimal (`%{clock, random}`) — the `from`/func/attempt travel inside the timer message, so concurrent executes are independent without per-call bookkeeping. Note: `func` runs in-process, so a slow `func` DOES block other callers; only the *wait* is non-blocking.
- **Key invariants tested**: immediate success = no retry (Counter==1); `max_retries: 0` ⇒ exactly 1 call; exhaustion returns `{:error, :max_retries_exceeded, last_reason}`; exact delay schedule 100/200/400/800 with `ZeroRandom` (jitter 0); `max_delay_ms:300` caps at 100/200/300/300/300; fixed jitter=50 ⇒ wait 150; concurrent fast-vs-slow don't block; last error reason propagates. Delays verified by recording `Clock.now()` per attempt into a named ETS table while advancing the fake clock between `assert_receive {:attempt_done, n}` steps (real `base_delay_ms: 1` so wall-clock is instant, logical time driven by Agent clock).
- **Variations (3)**: `013_002 TimeoutRetryWorker` — adds `:attempt_timeout_ms`(5000); each attempt runs in `Task.async` guarded by `Task.yield/2` + `Task.shutdown(:brutal_kill)`; timeout ⇒ `{:error, :timeout}` retry; also handles `{ref, result}`/`{:DOWN,...}` and tracks a `tasks` map (yield is synchronous, so it blocks the server up to the timeout). `013_003 BudgetRetryWorker` — total wall-clock `:budget_ms`(30_000) instead of max_retries; **decorrelated (AWS) jitter**: `:random` is 2-arity `(min,max)`, `next_delay = random(base_delay, prev_delay*3)`, `capped = min(next_delay, max_delay)`, refuses retry if `elapsed + capped > budget`; returns `{:error, :budget_exhausted, reason, attempts}`. `013_004 ClassifiedRetryWorker` — three-shape return `{:ok,_}`/`{:error,:transient,reason}`/`{:error,:permanent,reason}`; permanent stops immediately; exhaustion ⇒ `{:error, :retries_exhausted, reason}`; optional 3-arity `:on_retry.(attempt, reason, delay)` fired in-process before scheduling.
- **Notable**: `013_003` solution deviates from its own prompt — instead of `Process.send_after`, it does `spawn_link` + a **busy-wait** `await_clock/2` loop (`receive after 0 -> recurse`) polling the injected clock; retry loop is a recursive `do_attempt/9`. All others use the `<<<` bit-shift for `2^N`.

### tasks/014_* — Priority Queue Processors
- **Interface (014_001 `PriorityQueue`)**: `start_link(opts)` with `:name`, `:processor` (1-arity, default identity). `enqueue(server, task, priority)` with `priority in [:high,:normal,:low]` ⇒ `:ok`. `status/1 :: %{high:, normal:, low:}` (pending only, not the in-flight task). `drain/1` blocks until idle+empty (`:infinity`). `processed/1 :: [{task, result}]` in completion order.
- **Approach**: three `:queue` (Erlang FIFO) in `state.queues` keyed by level; `pop_highest` scans `[:high,:normal,:low]` via `Enum.find_value`. Async single-worker loop: `enqueue` → `maybe_trigger_processing` sends `:process_next` only if idle; `handle_info(:process_next)` `spawn_monitor`s the processor, which `send`s `{:task_result, self(), result}` back; on `{:DOWN, ref, ...}` it records the result and either re-triggers `:process_next` or flips `processing: false` and replies to queued `drain_waiters`. Only one task runs at a time; `processing` boolean gates triggering.
- **Key invariants tested**: FIFO within a level; strict `:high > :normal > :low` (tests use a "gate" process the processor blocks on so tasks pile up deterministically, then `Process.exit(gate, :kill)` releases them); `status` counts exclude the running task; `drain` on empty returns immediately; 50 concurrent `Task.async` enqueues lose nothing.
- **Variations (3)**: `014_002 ExpiringPriorityQueue` — per-task TTL; `enqueue(server, task, priority, opts)` with `:ttl_ms` (default `:default_ttl_ms`=5000), entries stored as `{task, expires_at}` using injected `:clock`; `pop_next_valid` recursively skips expired entries into an `expired` list; adds `expired/1` and `status.expired`. `014_003 CancellablePriorityQueue` — **numeric** priorities (0 = highest, dynamic `%{priority => :queue}` map, `Enum.sort` on keys); `enqueue ⇒ {:ok, ref}` (`make_ref/0`), `cancel(server, ref) :: :ok | {:error, :not_found}` (removes pending only, via `find_and_remove` + `clean_empty_queues`), `peek/1 :: {:ok, task, priority} | :empty`, `status` has `%{pending, by_priority, cancelled}`. `014_004 ConcurrentPriorityQueue` — `:max_concurrency`(1, validated pos int); levels renamed `:critical > :normal > :low`; tracks `active_workers` (`pid => {task, ref}`) and `pending_results` (result buffered on `{:task_result}`, finalized on `{:DOWN}`); `status` adds `active`/`max_concurrency`; completion order may differ from start order.
- **Notable**: all four run the processor in a `spawn_monitor`ed child (async), despite `014_001`'s prompt saying "called synchronously inside handle_info"; `{:task_result}` and `{:DOWN}` are decoupled so the result arrives before the monitor-down finalizes it. `drain` implemented by parking callers in `drain_waiters` and replying on quiescence.

### tasks/015_* — Service Monitors
- **Interface (015_001 `Monitor`)**: `start_link(opts)` with `:clock`, `:name`, `:notify` (`fn name, reason -> _` fired on `:down` transition). `register(server, name, check_func, interval_ms, max_failures \\ 3) :: :ok | {:error, :already_registered}`; `check_func` 0-arity ⇒ `:ok | {:error, reason}`. `status(server, name) :: {:ok, %{status: :up|:down|:pending, last_check_at, consecutive_failures}} | {:error, :not_found}`. `statuses/1`, `deregister/2` (idempotent `:ok`).
- **Approach**: `state = %{services: %{}, clock, notify}`; each service record holds `check_func, interval_ms, max_failures, status, last_check_at, consecutive_failures, notified_down`. Registration schedules `Process.send_after(self(), {:check, name}, interval_ms)`; `handle_info({:check, name})` looks the service up (missing ⇒ silently discard, which is how deregister cancels timers), runs `check_func` in-process, applies result, then re-schedules. `apply_check_result`: `:ok` ⇒ status `:up`, failures 0, `notified_down: false`; `{:error, r}` ⇒ increment, and at `failures >= max_failures` set `:down`; `notify?` is `threshold_reached && !notified_down` (exactly-once per down-run, re-armed on recovery via the reset flag).
- **Key invariants tested**: starts `:pending`; no double-register; `:up` after success; `:down` exactly at Nth consecutive failure; notify fires once, not on subsequent failures; custom `max_failures`; recover `:down`→`:up`; re-arm notify after recovery (`[{"api",:crash},{"api",:oom}]`); a success mid-run resets the counter; deregister removes + a stale `{:check, name}` is a no-op (0 notifications); re-register after deregister; per-service independence; `last_check_at` tracks clock; notify carries the *final* failure's reason. Tests drive checks manually via `trigger_check` (`send(mon, {:check, name})` then a `status` call to synchronize).
- **Variations (3)**: `015_002 RateMonitor` — rolling-window failure *rate* instead of consecutive count; `register(..., opts)` with `:window_size`(5)/`:threshold`(0.6); bounded `history` of `:ok`/`:error` (`Enum.take(-window_size)`); `:down` only when `window_full && rate >= threshold`; `status_info` has `:failure_rate`/`:checks_in_window`; `:notify.(name, failure_rate)`. `015_003 AsyncMonitor` — each check runs in a spawned `Task.start` with `:timeout_ms`(5000) via a separate `Process.send_after {:check_timeout, name, ref}`; task sends `{:check_result, name, ref, result}`; on timeout `Process.exit(pid, :kill)` ⇒ `{:error, :timeout}`; stale-`ref` results discarded; `status_info.check_in_flight`; one task per service; deregister kills in-flight task. `015_004 ManagedMonitor` — adds pause/resume + maintenance windows; internal split of `mode :: :active|:paused|:maintenance` vs `health :: :pending|:up|:down`; reported `status` is `:paused`/`:maintenance` overlay else `health`; `pause` skips check execution (timer still fires), `maintenance(server, name, duration_ms)` runs checks but suppresses failure counting/`:down` (successes still recover), auto-expires via `{:maintenance_end, name}`; `:notify` is 3-arity `(name, event, detail)` for `:down`/`:recovered`/`:maintenance_started`/`:maintenance_ended`; `resume` returns `{:error, :not_paused}` when active.
- **Notable**: uniform "look up service in map; if absent, drop the message" pattern is how all four cancel timers without holding timer refs. `015_003` also `try/rescue/catch`-wraps the check to convert exceptions to `{:error, {:exception, msg}}` and monitors the task but ignores `{:DOWN,...}` (lifecycle driven by result/timeout messages). Only `015_001`/`015_004` have `max_failures` as a positional 5th arg; `015_002`/`015_003` take it (or window opts) via a trailing `opts` keyword list.

## Groups 031–034 — Data Import, Ecto Ingestion & Log Analysis

Self-contained file-processing tasks: parse/validate tabular or line-delimited data (CSV/JSONL/JSON/logfmt), bulk-ingest into Ecto, or fold a structured file into an analysis report. Common thread: split good records from bad without ever raising, return a `{:ok, result}` / `{:error, reason}` shape, and cover the same edge-case surface (missing file, empty file, malformed rows, header/blank handling, quoted fields, BOM). All 13 directories are `d=01` full single-shot tasks that ship a `test_harness.exs`; there are **no fill-in-the-middle subtasks (`d=02+`)** in this cluster, and the `b=001..004` dirs are *distinct problems* in each family, not trivial rewordings. External deps used: `:nimble_csv` (031/032 CSV), `Jason` (JSONL/JSON), `Ecto` + `Ecto.Adapters.SQLite3` (032 test repos). Pure-stdlib only for 034. No OTP/GenServer/Agent/ETS anywhere except 032_003's `Task.async_stream` for parallel batches; no injected clocks (timestamps taken from `NaiveDateTime.utc_now/0`, tests `Process.sleep(2000)` to force >1s separation).

### tasks/031_* — CSV/JSONL/logfmt Importers with Schema Validation
- **Interface (per variation):** all expose a file+string pair returning `{:ok, valid, error_report} | {:error, :file_not_found | :empty_file}`, where `error_report` is `[{row_or_line_number, field_name, error_message}]` (1-based data rows/lines).
  - 031_001 `CsvImporter.import_file/2` & `import_string/2` — valid rows are `%{header_string => trimmed_string_value}`.
  - 031_002 `JsonlImporter.import_file/2` & `import_string/2` — one JSON object per line; valid records keep decoded values; adds `:list` type.
  - 031_003 `CsvLoader.load_file/2` & `load_string/2` — **coerces** values to native Elixir types; valid rows are **atom-keyed** (`:key` field or `String.to_atom(name)`) with typed values; extra types `:date`, `:enum` (needs `:values`).
  - 031_004 `LogfmtValidator.validate_file/2` & `validate_string/2` + public `parse_logfmt_line/1` — space-separated `key=value`, quoted values, bare keys → `"true"`.
- **Approach:** shared schema = list of field maps `%{name, required (default true), type (default :string), format}`; `:format` accepts a `Regex` or atom `:email` (permissive regex `~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/`). 031_001/003 use `NimbleCSV.define(<Mod>.Parser, separator: ",", escape: "\"")`; single-pass `Enum.reduce` accumulating `{valid, errors}`. 031_004 is a **hand-written recursive parser** (`do_parse/2`, `parse_key`, `parse_value`) — deliberately does *not* `trim_leading` after `=` so a leading space means empty value.
- **Key invariants tested:** all validation errors reported per field (not first-only); exact messages `"is required"`, `"must be a valid <type>"`, `"does not match expected format"`; type rules — integer via `Integer.parse` w/ `{_,""}`, float accepts integer-formatted strings, boolean ∈ `~w(true false 1 0)` case-insensitive; row shorter than header → missing cols empty, longer → extras dropped; required checks whitespace-only as empty; type/format checks skipped on empty values; UTF-8 BOM `\xEF\xBB\xBF` stripped; header-only file → `{:ok, [], []}`; whitespace trimmed; quoted commas/newlines survive; 500-row scale test (031_001).
- **Variations:** 4 (csv importer / jsonl importer / csv loader+coercion / logfmt validator) — see interfaces above.
- **Subtasks:** none.
- **Notable:** 031_001 guards NimbleCSV (raises on empty) with a manual `String.split(~r/\r?\n/, parts: 2)` pre-check for the header-only case; valid-row map filtered to schema fields actually present in headers.

### tasks/032_* — File → Ecto Bulk/Batch Ingestion Pipelines
- **Interface:** `<Mod>.ingest(repo, schema, file_path, opts \\ [])` → `{:ok, stats}` | `{:error, reason}`; stats is an integer-keyed map (keys differ by variation).
  - 032_001 `DataIngestion` — JSON array file; `stats = %{total, inserted, updated, failed}`.
  - 032_002 `CsvIngestion` — CSV via NimbleCSV, each row validated through an **Ecto changeset**; `stats = %{total, inserted, invalid, failed}` (`:invalid` = changeset-rejected).
  - 032_003 `JsonlIngestion` — `File.stream!/1` line-by-line + `Jason.decode/1`, **optional parallelism**; `stats = %{total, inserted, skipped, failed}`.
  - 032_004 `MultiSchemaIngestion.ingest(repo, routing, file_path, opts)` — `routing = %{type_string => schema_module}`; `stats = %{total, by_schema: %{schema => %{inserted, failed}}, unroutable, missing_type}`.
- **Approach:** `with`-chain: `read_file` → `parse` → validate top-level list → `Enum.chunk_every(batch_size)` → `repo.insert_all/3` per batch inside `try/rescue/catch` (a failing batch adds its size to `:failed`/`:invalid` and continues — partial success is still `{:ok, stats}`). `prepare_rows` filters JSON string keys to `schema.__schema__(:fields)` (compared as strings, atomised via `String.to_existing_atom` — never `to_atom` on untrusted input) and injects `inserted_at`/`updated_at` (since `insert_all` skips callbacks/timestamps). insert vs update told apart via `returning: true` + comparing returned `inserted_at`/`updated_at` within `@insert_window_seconds = 1`. `require Logger`; `Logger.info` after each batch with running totals.
- **Opts:** `:batch_size` (default 500), `:on_conflict` (default `:replace_all`), `:conflict_target` (default `:nothing`), `:returning` (default true, 032_001); 032_003 adds `:max_concurrency` (default 1) + `:timeout` and switches to `Task.async_stream(..., max_concurrency:, timeout:)` when `>1`; 032_004 adds `:type_field` (default `"type"`) and per-schema `conflict_target` map, groups via `Enum.group_by` on the discriminator.
- **Key invariants tested:** `{:error, :file_not_found | :invalid_json | :not_a_list}`; empty array → all-zero stats; batch boundaries honored (e.g. batch_size 5 with a NOT-NULL-violating middle batch → `failed: 5`, others still inserted); upsert path (`on_conflict: {:replace_all_except, [:inserted_at]}`) yields `updated >= 5`. Tests spin an in-memory SQLite repo (`:memory:`), `CREATE TABLE widgets` with `external_id UNIQUE`, `async: false`.
- **Variations:** 4 (json bulk / csv+changeset / jsonl streaming+parallel / multi-table discriminator routing).
- **Subtasks:** none.
- **Notable:** 032_001 `get_ts/2` reads either atom- or string-keyed returned rows; timestamp-window trick is the load-bearing mechanism for insert/update classification and is why the upsert test sleeps 2s.

### tasks/033_* — Structured File Analyzers (log / metrics / HTTP / financial)
- **Interface:** one public fn, `<Mod>.analyze/1` (033_002 is `summarize/1`), `(path) → {:ok, report_map} | {:error, reason}`. Report is a plain map with a fixed key set.
  - 033_001 `LogAnalyzer.analyze/1` → `%{counts_by_level, error_rate, top_errors, time_range, errors_per_hour, malformed_count}`.
  - 033_002 `MetricAggregator.summarize/1` → `%{per_metric: %{name => %{count,min,max,sum,mean}}, total_samples, time_range, samples_per_hour, unique_tags: %{tag_key => MapSet}, malformed_count}`.
  - 033_003 `AccessLogAnalyzer.analyze/1` → `%{requests_by_method, requests_by_status, top_paths, avg_duration, max_duration, error_rate, error_count, time_range, malformed_count}` (error = status ≥ 400).
  - 033_004 `TransactionAnalyzer.analyze/1` → `%{balance_by_account, volume_by_currency, transaction_count, top_accounts, time_range, malformed_count}` (`type ∈ {"credit","debit"}`, `amount > 0`).
- **Approach:** `File.stat(path)` first for a clean `{:error, reason}` (since `File.stream!/3` is lazy), then `File.stream!([], :line)` → trim `\n`/`\r` → `Enum.reduce(initial_acc/0, &process_line/2)` → `build_report/1`. Each line is an independent JSON object decoded by `Jason.decode/1`; single streaming pass keeps counts, min/max timestamps `{min_dt,max_dt}`, per-hour buckets keyed `{{y,m,d}, hour}` (UTC). `top_*` sorted **descending by count, then ascending by key alphabetically**, `Enum.take(10)`.
- **Key invariants tested (033_001 fixture):** counts per level exact; `error_rate = errors / valid_lines` (5/9); `malformed_count` counts bad-JSON + missing-field lines (2) but **blank/whitespace lines skipped silently, not malformed**; `top_errors` tie broken alphabetically, capped at 10 distinct; `time_range` earliest/latest across all valid lines (`nil` if none); `errors_per_hour` only hours with ≥1 error, spans calendar days. Timestamp parse via `DateTime.from_iso8601/1` then `DateTime.shift_zone!(dt, "Etc/UTC")`; malformed if not a JSON object, any required field absent, or timestamp unparseable/non-string.
- **Variations:** 4 (log levels / numeric metrics stats / HTTP traffic / financial ledger) — same streaming skeleton, different accumulators and report keys.
- **Subtasks:** none.
- **Notable:** identical fold-over-stream architecture reused across all four; 033_003 classifies via `status_code >= 400`; 033_002 accumulates running `%{count,min,max,sum}` then derives `:mean = sum/count` at report time.

### tasks/034_001 — Data Reconciliation Engine
- **Interface:** `Reconciler.reconcile(left, right, opts)` (both lists of maps, `opts` keyword) → `%{matched: [%{left, right, differences}], only_in_left: [record], only_in_right: [record]}`. `differences` is `%{field => %{left: val, right: val}}` (empty if equal on all compared fields).
- **Opts:** `:key_fields` (**required**, non-empty list of atoms; validated via `fetch_key_fields!` which raises `ArgumentError` on missing/non-list/non-atom) forming a **composite key**; `:compare_fields` (optional; defaults to `(keys(left) ∪ keys(right)) − key_fields`).
- **Approach:** pure/stdlib only, no processes. `index_by/2` builds `%{composite_key_tuple => record}` where key is `key_fields |> Enum.map(&Map.get) |> List.to_tuple()` (1-tuple even for single key, avoids collisions); set algebra on `MapSet` of keys → intersection/difference gives matched/only-left/only-right; `diff/3` folds fields comparing with `==`, missing field treated as `nil`.
- **Key invariants tested:** exact + composite-key matching (`[:org_id,:user_id]` matches only when both equal); matched entries carry **full original left/right** even when `compare_fields` excludes fields; identical records → `differences == %{}`; a field present on one side only → `%{field => %{left: v, right: nil}}`; empty/disjoint lists; result order irrelevant.
- **Variations:** 1 (only 001). **Subtasks:** none.
- **Notable:** duplicate keys resolved last-write-wins (documented as intentional for the side-effect-free contract).

## Groups 035–045 — Data Transforms & ETS-Backed Modules

Eleven single-shot tasks (all `_01`, each with prompt.md + solution.ex + test_harness.exs; **no `_02+` variations and no fill-in-the-middle subtasks exist in this range**). Families 035–040 are pure, dependency-free data-transformation modules (single public function, no processes); families 041–045 are OTP modules where a GenServer owns one or more `:named_table` ETS tables and the "hot path" (reads / atomic counters) bypasses the process by hitting ETS directly, while mutations serialise through `GenServer.call`. Recurring design idioms: deterministic-without-a-clock (monotonic integer counter in 041; SHA-256/`phash2` hashing in 037/045), `:persistent_term` used to publish the server pid / ETS tid so public functions avoid a GenServer round-trip (042, 045), and lazy `:ets.new` on first use (042). Stdlib/OTP only, no external deps anywhere.

### 035_001_time_series_resampler — Time Series Resampler
- **Interface**: `TimeSeriesResampler.resample(data, interval_ms, opts \\ []) :: [{bucket_start_ms, value | nil}]`. `data` = `[{ts_ms, number}]` any order; `opts` = `[agg: mode, fill: mode]`.
- **Approach**: sort by ts; bucket = `div(ts, interval) * interval` (`floor_bucket`); `Enum.group_by` into buckets; walk grid with `Stream.iterate(&(&1+interval)) |> take_while(<= last_bucket)` and `Enum.map_reduce` carrying `last_value` for forward-fill. `:agg` ∈ `[:last, :first, :mean, :sum, :count, :max, :min]` (default `:last`); `:fill` ∈ `[:nil, :forward]` (default `:nil`). `resample([], …) → []`.
- **Key invariants tested**: every bucket between first & last present even if empty; boundary point at exact `interval` goes to the higher bucket; reverse-order input == sorted input; `:forward` carries last non-empty agg value (nil if leading gap); `:mean` is float via `sum/count`.
- **Variations**: none. **Subtasks**: none.
- **Notable**: `@valid_fill [:nil, :forward]` — tests pass `fill: nil` which works because `:nil == nil` in Elixir. Raises `ArgumentError` for non-positive/non-integer `interval_ms` or bad opt values (`fetch_opt!`).

### 036_001_markdown_to_structured_data_parser — Markdown → Structured Data
- **Interface**: `MarkdownParser.parse(markdown :: binary) :: [%{category: String.t(), items: [%{name, description, tags}]}]`.
- **Approach**: `split("\n") → trim_trailing → classify_line → reduce`. Two module regexes: heading `~r/^##\s+(.+)$/`, item `~r/^-\s+\*\*(.+?)\*\*:\s+(.*?)(?:\s+\(([^)]*)\))?\s*$/` (bold name, description, optional trailing `(tags)`). Fold with state `%{categories, current}`; items prepended then `Enum.reverse` in `finalise`.
- **Key invariants tested**: only H2 defines categories (H1/H3+ ignored as unrecognized); empty H2 → `items: []`; bullets before first heading discarded; tags split on `,` + individually trimmed + empty rejected (no parens → `[]`); nested/indented `  -` and non-bold bullets ignored; CRLF handled (trim_trailing strips `\r`); `parse("") → []`.
- **Variations**: none. **Subtasks**: none.
- **Notable**: single-`-`-only match enforced by regex anchor `^-\s+`.

### 037_001_data_anonymizer — Data Anonymizer
- **Interface**: `Anonymizer.anonymize(records :: [map], rules :: %{atom => rule}) :: [map]`. `rule` ∈ `:hash | :mask | :redact | {:fake, seed}`.
- **Approach**: `Enum.map` records, per record `Enum.reduce(rules, …)` applying `apply_rule/2`; missing field silently skipped (`Map.fetch` → `:error` passes through). `:hash` = `:crypto.hash(:sha256, to_string(v)) |> Base.encode16(case: :lower)`; `:mask` keeps first+last, middle → `*` (len 0 unchanged, 1 → `"*"`, 2 → as-is); `:redact` → `"[REDACTED]"`; `{:fake, seed}` = `generate_fake` hashes `"#{inspect(seed)}:#{value}"` with SHA-256, uses successive bytes b0..b6 to index `@first_names`/`@last_names`/`@domains` word-lists and pick one of 4 output formats (`rem(b2,4)`).
- **Key invariants tested**: referential integrity for all 4 rules (same value → same output, driven by purity of hashing); different seeds / different values → different fakes; untouched fields passthrough; empty records → `[]`; empty rules → unchanged.
- **Variations**: none. **Subtasks**: none.
- **Notable**: determinism achieved purely via hashing (no RNG/clock). No external Faker dependency — hand-rolled word lists.

### 038_001_tree_structure_builder_from_flat_list — Tree Builder from Flat List
- **Interface**: `TreeBuilder.build(items, opts \\ []) :: {:ok, forest} | {:error, {:cycle_detected, ids}}`. Nodes are `%{id, parent_id, ...}`; output adds `:children`. Opt `:orphan_strategy` ∈ `:discard` (default) | `:raise_to_root`.
- **Approach**: `index_items` (id→node map + ordered id list); `detect_duplicate_ids` (returns `{:error, {:duplicate_ids, dupes}}`); `build_children_map` (parent_id → child ids in input order via `++`); **iterative-ish white/grey/black DFS `detect_cycle`/`dfs`** with `extract_cycle` reconstructing cycle ids top-down from the ancestor stack; roots = nodes with `nil` parent_id OR (unknown parent_id AND strategy `:raise_to_root`); `build_subtree` recurses.
- **Key invariants tested**: direct (A→B→A) & indirect (A→B→C→A) cycles detected, ids reported; no false positives on deep chains (1..20), wide fans (50 siblings), diamonds; children & roots preserve input order; all original fields preserved; child-first input still builds; string/atom/int ids; orphans discarded vs raised (raised orphan keeps its own subtree).
- **Variations**: none. **Subtasks**: none.
- **Notable**: cycle detection runs on the `parent→children` graph before any tree construction. `:children` key is only added, never a full node rebuild.

### 039_001_diff_generator_for_record_lists — Diff Generator for Record Lists
- **Interface**: `RecordDiff.diff(old_list, new_list, opts \\ []) :: %{added: [rec], removed: [rec], changed: [entry]}`. Opt `:key` (default `:id`). `entry = %{<key> => key_value, changes: %{field => {old, new}}}`.
- **Approach**: `index_by` both lists into `%{key_value => record}` (`Map.fetch!` on key); MapSet diff/intersection on key sets; `map_set_to_records` **sorts keys** for deterministic order; `changed_entries` compares via `diff_records` (union of both records' keys, `Map.get(…, :missing)` for absent side, drops equal fields); identical records omitted.
- **Key invariants tested**: identical/empty → all-empty diff; added/removed/disjoint sets; multi-field changes; unchanged records excluded from `:changed`; field added → `{:missing, new}`, removed → `{old, :missing}`; custom `:key` (`:uuid`); mixed add+remove+change scenario. Pure — no processes.
- **Variations**: none. **Subtasks**: none.
- **Notable**: `:missing` atom is the sentinel for field presence changes; determinism via `Enum.sort` on keys.

### 040_001_configuration_merger_with_override_rules — Configuration Merger
- **Interface**: `ConfigMerger.merge(base, override, opts \\ []) :: map`. Opts: `:list_strategy` ∈ `:replace` (default) | `:append`; `:list_strategies` = `%{key_path => strategy}`; `:locked` = `[key_path]`. Key paths are lists of atoms (root→target), e.g. `[:app, :auth, :secret_key]`.
- **Approach**: `resolve_opts` validates & normalises (accepts both list `[:a,:b]` and tuple `{:a,:b}` paths via `normalise_path`); `do_merge` unions keys, tracks `current_path`, `cond`: base-only kept, override-only added, else lock check then `merge_values`. `merge_values`: map+map → recurse; list+list → `list_strategy_for` (per-key beats global) `:replace`→override / `:append`→`base ++ override`; else override wins (scalars, type mismatch).
- **Key invariants tested**: scalar override; deep 3–4 level merge preserves untouched branches; list replace default vs append (global & per-key & nested paths); locked top-level & nested keys keep base value; lock at one path doesn't protect same key name elsewhere; multiple locks; append+lock combined; empty override → base, empty base → override.
- **Variations**: none. **Subtasks**: none.
- **Notable**: raises `ArgumentError` on bad strategy value or malformed path. Locking only applies when key exists in both maps.

### 041_001_lru_cache_backed_by_ets — LRU Cache Backed by ETS
- **Interface** (GenServer): `start_link(name:, max_size:)` (both required); `get(name, key) :: {:ok, value} | :miss`; `put(name, key, value) :: :ok`. Provides `child_spec/1`.
- **Approach**: **two ETS tables** — `:"#{name}_data"` (`:set, :public, read_concurrency`) `key → {value, ts}` for O(1) reads, and `:"#{name}_order"` (`:ordered_set, :protected`) `ts → key` for O(log n) eviction. **Monotonic integer `counter` in state = the "timestamp"** (no wall clock → deterministic). `get` reads ETS directly then `GenServer.call({:touch, key})` to refresh order (re-checks existence, deletes old ts row, inserts new). `put` via call: existing key updates value + ts; new key runs `maybe_evict` (if `:ets.info(size) >= max_size`, evict `:ets.first(order_table)` = smallest ts = LRU) then inserts. `next_counter` increments.
- **Key invariants tested**: `:miss` on unknown; overwrite; LRU eviction order; **`get` promotes to MRU** (saves entry from eviction); `put` on existing key refreshes recency; size-1 cache; arbitrary terms incl `nil` key/value; two instances independent (unique per-test names).
- **Variations**: none. **Subtasks**: none.
- **Notable**: explicitly clock-free by design (prompt calls it out). Tests `async: false`.

### 042_001_ets_based_write_through_cache_layer — Write-Through Cache Layer
- **Interface** (GenServer): `start_link(opts \\ [])`; `fetch(server, table, key, fallback_fn) :: {:ok, value}`; `invalidate(server, table, key) :: :ok`; `invalidate_all(server, table) :: :ok`. `table` = atom, `fallback_fn` = 0-arity.
- **Approach**: one ETS `:set, :public` table per `table` atom, created **lazily** in `ensure_table` on first `:fetch`. Tid published via `:persistent_term.put({CacheLayer, self(), table}, tid)`; `fetch` resolves server→pid (`resolve_pid!` via `GenServer.whereis`), reads that persistent_term then hits ETS directly on hit. **Cache miss → `GenServer.call({:fetch, …})` which re-checks ETS then calls `fallback_fn.()` at-most-once**, inserts result. `terminate/2` (traps exits) deletes tables + erases persistent_term entries.
- **Key invariants tested**: miss calls fallback once & stores; hit doesn't recall; fallback value stored/returned; `nil` is a valid cached value (no re-call); invalidate single key re-triggers fallback, leaves others; `invalidate_all` clears table; invalidate/invalidate_all on absent key/table → `:ok`; table namespaces independent (same key diff table = 2 misses); lazy creation. Test uses an `Agent` `CallTracker` to count fallback invocations.
- **Variations**: none. **Subtasks**: none.
- **Notable**: at-most-once guarantee comes from the GenServer re-checking ETS under serialisation. Unnamed ETS tables (tids tracked in state) to avoid cross-instance atom collisions.

### 043_001_ets_based_leaderboard — ETS-Based Leaderboard
- **Interface** (no GenServer — pure ETS): `new(board_name :: atom) :: {:ok, board}`; `submit_score(board, player_id, score) :: :ok`; `top(board, n) :: [{player_id, score}]`; `rank(board, player_id) :: {:ok, rank, score} | {:error, :not_found}`.
- **Approach**: `:ets.new(name, [:set, :public, :named_table, read_concurrency])` → tid is the `board`. `submit_score` uses **`:ets.insert_new` fast path** (fresh key), else atomic conditional overwrite via `:ets.select_replace` with match spec guarding `{:>, score, :"$1"}` (keep personal best; float-safe, avoids `update_counter`). `top` = `tab2list |> sort_by(score, :desc) |> take(n)` (`top(_,0)→[]`). `rank` looks up player then `:ets.select_count` of players with strictly-greater score, `+1` = **standard competition ("1224") ranking**.
- **Key invariants tested**: empty top; desc sort; `top(n)` caps & returns all if fewer; higher score overwrites, lower/equal no-op; convergence to personal best; rank 1-based, ties share rank; not-found; player_id type independence (`"1"` vs `1` vs `:one`); board isolation; score 0 & negatives; 1000-player scale.
- **Variations**: none. **Subtasks**: none.
- **Notable**: concurrency achieved purely through atomic ETS ops (`insert_new`, `select_replace`) — no GenServer. Uses `:named_table` so second board needs distinct atom (tests use `unique_integer`).

### 044_001_ets_based_metrics_collector — ETS-Based Metrics Collector
- **Interface** (GenServer owns table only): `start_link(opts \\ [])` (`:name` default `__MODULE__`); `increment(name, amount \\ 1) :: :ok`; `gauge(name, value) :: :ok`; `get(name) :: number | nil`; `all() :: map`; `reset(name) :: :ok`; `snapshot() :: map`.
- **Approach**: single fixed table `@table __MODULE__` created in `init` as `[:set, :named_table, :public, read_concurrency: true, write_concurrency: true]`. **Hot path bypasses GenServer entirely** — `increment` = `:ets.update_counter(@table, name, {2, amount}, {name, 0})` (atomic, default row `{name,0}`); `gauge`/`reset` = `:ets.insert`; `get` = `:ets.lookup`; `all`/`snapshot` = `tab2list |> Map.new` (snapshot is just an alias for `all`, semantic-only).
- **Key invariants tested**: increment creates-at-1 / adds amount / defaults 1; reset → 0 for counter & gauge & unknown; gauge exact/overwrite/decrease/zero; get nil unknown; all/snapshot maps; snapshot is a point-in-time copy (later mutation doesn't change captured map); key independence; **100 concurrent `Task.async` increments == 100** (atomicity); mixed concurrent counters+gauges.
- **Variations**: none. **Subtasks**: none.
- **Notable**: `increment` guard `is_integer(amount) and amount >= 0` (monotonic). Only OTP module here that never routes any operation through the process after init. Tests `async: false`, `start_supervised!(Metrics)`.

### 045_001_ets_based_feature_flag_store — ETS-Based Feature Flag Store
- **Interface** (GenServer): `start_link(opts \\ [])` (`:table_name` default `:feature_flags`, `:name` default `__MODULE__`, `name: nil` skips registration); `enable/1`, `disable/1`, `enable_for_percentage/2` (0..100 int); `enabled?/1 :: boolean`; `enabled_for?/2 :: boolean`.
- **Approach**: table created in `init` as `[:set, :named_table, :public, read_concurrency: true]`. **Writes serialise** through `handle_call({:set, flag, value})`; values stored as `{:on} | {:off} | {:percentage, n}`. **Reads hit ETS directly** (`lookup/1`). Server pid & table published via `:persistent_term` (`@pt_server`, `@pt_table`) so public write fns reach the server without a fixed registered name. Percentage bucket **deterministic** via `:erlang.phash2({flag_name, user_id}, 100) < pct`.
- **Key invariants tested**: unknown → false; enable/disable global; `enabled?` false for percentage flags; 0% none / 100% all; 50% ≈ half (400–600 of 1000); determinism (two passes equal); exact `phash2` formula match; state transitions on→percentage→off; percentage update takes effect immediately; flag independence; concurrent reads consistent.
- **Variations**: none. **Subtasks**: none.
- **Notable**: `persistent_term`-based server discovery lets tests start with `name: nil`. Deterministic rollout via `phash2` (no RNG/clock). Tests `async: false`.

## Groups 061–075 — Concurrency, Saga & Testing Utilities

Ten self-contained single-file Elixir tasks split into two themes: hand-rolled OTP concurrency primitives (061–064) and testing/utility infrastructure (070–075). The concurrency tasks all reimplement scheduling/timeout/work-distribution logic from scratch (no `Task.async_stream`), stressing ordered results, crash isolation, and no-zombie guarantees. The testing utilities cover the Saga pattern plus ExMachina-style factories, injectable clocks, DB cleaners, custom ExUnit macros, and StreamData generators. Every family has ONLY the `_01` original single-shot dir (prompt.md + solution.ex + test_harness.exs); there are NO `b≥02` problem variations and NO `d≥02` fill-in-the-middle subtasks in this cluster. All solutions are stdlib/OTP-only except 075 (depends on `stream_data`) and 073/074 (assume Ecto types present, but tests use fakes).

### 061 — ParallelMap (parallel map with concurrency limit)
- **Interface**: `ParallelMap.pmap(collection, func, max_concurrency)` → results list in input order; per-element `{:error, reason}` on crash. Helper GenServer `ConcurrencyCounter` with `start_link(opts)` (accepts `:name`), `increment/1`, `decrement/1` (return new count), `peak/1` (highest ever). Guards: `is_function(func,1)`, `max_concurrency >= 1`.
- **Approach**: NOT `Task.async`; uses `spawn_monitor` so task crashes deliver only a `:DOWN` message, never propagate. Each spawned fn wraps `func.(elem)` in try/rescue/catch → sends `{our_ref, {:ok,val}|{:error,reason}}` to parent (own `make_ref()` as message key, monitor ref kept alongside). Seed = first `max_concurrency` elements via `Enum.split`; `collect/5` recursion awaits one result then refills the freed slot from the queue. `running` map `%{our_ref => {mon_ref, idx}}`; on result `Process.demonitor(mon_ref, [:flush])`. Reassembles via `Enum.map(0..total-1, &Map.fetch!(raw,&1))`.
- **Key invariants tested**: order preserved even when tasks finish out-of-order (later indices sleep less); `peak <= max_concurrency`; `peak >= 2` proves real parallelism; `max_concurrency=1` → peak exactly 1; single crash doesn't cancel siblings; all-crash returns all error tuples; empty collection → `[]`.
- **Variations**: none. **Subtasks**: none.
- **Notable**: `await_one` also handles external `Process.exit(pid,:kill)` by locating the entry via monitor ref (`Enum.find`). `ConcurrencyCounter.decrement` intentionally does NOT touch peak. `async: false` test file.

### 062 — Pipeline (pipeline processor with stages)
- **Interface**: `Pipeline.new()` → `%Pipeline{stages: []}` (`@enforce_keys [:stages]`); `Pipeline.stage(pipeline, name, fun)` (name atom, `fun/1` → `{:ok,res}|{:error,reason}`, stored in insertion order via `stages ++ [{name,fun}]`); `Pipeline.run(pipeline, input)` → `{:ok, final, [%{stage: atom, duration_us: non_neg_integer}]}` or `{:error, failed_stage_name, reason}`.
- **Approach**: Pure module, no processes/GenServer. `execute/3` tail-recursion threading value + reversed meta accumulator. Per-stage timing via `:timer.tc(fn -> fun.(value) end)` (microseconds). On `{:error,reason}` halts immediately returning 3-tuple (metadata NOT returned on error). Invalid stage return (not ok/error tuple) raises `ArgumentError`.
- **Key invariants tested**: results thread correctly; metadata ordered by execution, one per executed stage; empty pipeline returns input unchanged with `[]`; stages after failure never called (Agent flag); sleeping stage → `duration_us >= 9_000` for 10ms sleep; works with map/list inputs.
- **Variations**: none. **Subtasks**: none.
- **Notable**: `async: true`. Comment in code notes metadata is deliberately dropped from the error tuple to honor the strict 3-element spec.

### 063 — ConcurrentFetcher (concurrent data fetcher with global timeout)
- **Interface**: `ConcurrentFetcher.fetch_all(sources, timeout_ms)` where `sources :: [{name, zero_arity_fetch_fn}]`, name any term. Returns `%{name => {:ok,value}|{:error,:timeout}|{:error,reason}}`. Empty sources → `%{}` immediately. Guards: `is_list`, `is_integer(timeout_ms) and >= 0`.
- **Approach**: `Task.async/1` per source (linked to caller). `safe_call/1` normalizes fetch_fn return (`{:ok,_}|{:error,_}`, else `{:error,{:unexpected_return,other}}`) with rescue→`{:error,exception}` and catch→`{:error,{kind,value}}`. Single **global** budget via `Task.yield_many(tasks, timeout_ms)` (one shared wall-clock, not per-source). `nil` yield outcome → `Task.shutdown(task, :brutal_kill)` then `{:error,:timeout}`; `{:exit,reason}` → `{:error,reason}`. Result map built keyed by `task.ref` then re-keyed to source names.
- **Key invariants tested**: fast fetches ok, slow → `:timeout`; 400ms ok / 600ms timeout under 500ms budget semantics; returns within `timeout+200ms` even with a 10s fetch; **no zombie processes** (compares `Process.list()` MapSet before/after, `Process.sleep(50)` for teardown); genuine concurrency (5×100ms < 300ms); arbitrary term keys (string/int/tuple).
- **Variations**: none. **Subtasks**: none.
- **Notable**: `async: true`. Relies on `Task.shutdown` synchronously killing + reaping to guarantee no leftover pids.

### 064 — WorkStealQueue (work-stealing task queue)
- **Interface**: `WorkStealQueue.run(items, worker_count, process_fn)` → list of `%{item, result, worker_id: 0..worker_count-1}` (any order), synchronous/blocking. Guards: `is_list(items)`, `worker_count > 0`, `is_function(process_fn,1)`.
- **Approach**: `partition/2` splits items evenly (first `rem(total,n)` chunks get +1), always returns exactly `n` lists (some `[]` when workers > items). Shared coordinator = `Agent` holding `%{worker_id => remaining_queue}`. Each worker = `Task.async` running `process_local_queue` tail-recursion with result accumulator; `Task.await_many(:infinity)` then `List.flatten`, then `Agent.stop`. Coordinator ops all atomic: `pop_item` (`get_and_update`, `[head|tail]` or `:empty`), `find_victim` (rejects self + empty queues, `Enum.max_by` on length → busiest), `steal_half` (`get_and_update`; if `len < 2` returns `[]`, else `Enum.split(queue, len - div(len,2))` steals back half). Thief prepends stolen items and resumes. Failed steal (`[]`) → retry with fresh scan; no victim → done.
- **Key invariants tested**: all items processed exactly once (`uniq_by`); `worker_id` in bounds; all workers used when items ≫ workers; `worker_count > item_count` still completes; single worker never steals (`worker_ids == [0]`); slow-vs-fast items → `max_count > min_count` proving stealing produced uneven distribution; empty items → `[]`.
- **Variations**: none. **Subtasks**: none.
- **Notable**: Steals from back (victim consumes front) so stolen items are furthest from imminent processing. `async: false`.

### 070 — Saga (saga compensating transaction coordinator)
- **Interface**: `Saga.new()` → `%Saga{steps: []}`; `Saga.step(saga, name, action_fn, compensate_fn)` (name atom, `action/1` → `{:ok,res}|{:error,reason}`, `compensate/1` → any; appended via `steps ++ [entry]`); `Saga.execute(saga, context)` (context must be a map) → `{:ok, final_context}` or `{:error, failed_step_name, reason, compensation_results}` where compensation_results is keyword list `[step_name: compensate_return]` in reverse execution order.
- **Approach**: Pure module + struct, no processes. `run_steps/3` threads context; on success merges `Map.put(context, name, result)` and prepends step to `completed` (already reverse order). `safe_action` normalizes non-ok/error returns to `{:error,{:unexpected_return,other}}` and rescues exceptions → `{:error,{:exception,e,stacktrace}}`. On failure `compensate_all/2` runs every completed compensation in reverse, each in try/rescue (`{:exception,e,st}`)/catch (`{:caught,kind,value}`) so a raising compensation never aborts the rest.
- **Key invariants tested**: enriched context threading (step sees prior results, e.g. `ctx.reserve`); compensations run reverse order for only-completed steps; failed step's own compensation NOT run (only prior); comp results reversed `[b: ..., a: ...]`; compensations receive context at point of failure; all compensations run even if one raises; first-step failure → `{:error,:a,_,[]}`; empty saga returns unchanged context.
- **Variations**: none. **Subtasks**: none.
- **Notable**: Tests use process dictionary (`Process.put/get`) for side-effect tracking to stay processless; `async: true`.

### 071 — Factory (factory module for test data generation)
- **Interface**: `Factory.build/1`, `build/2` (overrides keyword list), `insert/1`, `insert/2` (persists via `MyApp.Repo.insert!/1`), `sequence(name, formatter_fn)` (formatter gets monotonic int from 1; per-name independent counter), `start/0` (starts named Agent). Factories declared as private `factory/1` clauses returning structs.
- **Approach**: Named `Agent` `Factory.SequenceAgent` holds `%{name => counter}`; `sequence/2` uses `Agent.get_and_update` for atomic increment (async-safe). Lazy `ensure_agent_started/0` via `Process.whereis`. Association handled by **zero-arity thunks**: `:post` factory sets `user_id: fn -> insert(:user).id end`; `build/2` merges overrides FIRST (`struct(base, overrides)`) THEN `resolve_thunks/1` calls any remaining `is_function(_,0)` field — so passing `user_id:` override suppresses the implicit user insert. `@compile {:no_warn_undefined, MyApp.Repo}`; uses `struct!/2` at runtime to avoid compile-time schema dep. Built-in factories `:user` (name/email via sequences) and `:post` (title/body/user_id); unknown name raises `ArgumentError`.
- **Key invariants tested**: `build` no DB writes; overrides merge; `insert` returns id and adds record; sequences distinct + independent per name; default emails unique; `build(:post)` inserts one user (user_id populated); `insert(:post)` inserts ≥2 rows; `insert(:post, user_id: id)` skips auto-user (count +1 only); sequences safe under 50 concurrent tasks (all unique).
- **Variations**: none. **Subtasks**: none.
- **Notable**: test_harness defines stand-in `MyApp.User`/`MyApp.Post` structs, a `FakeRepo` Agent (auto-increment ids), and `MyApp.Repo` delegating `insert!` to FakeRepo. `async: false`.

### 072 — Clock (test helper for time-dependent code)
- **Interface**: behaviour `Clock` with `@callback now() :: DateTime.t()`. `Clock.Real.now/0` → `DateTime.utc_now()`. `Clock.Fake` GenServer: `start_link(opts)` (`:initial` default `~U[2024-01-01 00:00:00Z]`, optional `:name`), `now/1`, `freeze/2` (replace), `advance/2` (keyword duration). Dispatcher `Clock.now/1`: atom + `function_exported?(clock,:now,0)` → `clock.now()`, else `Clock.Fake.now(clock)`; non-atom (pid) → `Clock.Fake.now/1`.
- **Approach**: Fake state = single `%DateTime{}`. `advance` applies each `{unit, amount}` left-to-right via `DateTime.add(dt, amount, canonical)`; `@unit_aliases` map normalizes plural→singular (`seconds`→`:second`, etc.). Negative amounts allowed (time travel backward). Enables DI: app takes `:clock` option, calls `Clock.now(clock)` uniformly.
- **Key invariants tested**: Real.now within before/after bounds; Fake freeze/read stable; advance by seconds/minutes/hours cumulative & mixed; freeze-then-advance; dispatch to Real (module atom), pid, and registered name; two Fake instances fully isolated; DI `Greeter.greet` returns morning/afternoon/evening from frozen clock.
- **Variations**: none. **Subtasks**: none.
- **Notable**: One isolation test uses wrong `Clock.Fake.now(clock: c1)` keyword form guarded by `rescue -> :ok` (accepts either calling convention). `async: true`.

### 073 — DBCleaner (database cleaner for integration tests)
- **Interface**: `DBCleaner.start(strategy, opts \\ [])` (strategy `:transaction`|`:truncation`; opts `:repo` required atom, `:tables` list of strings) → `{:ok, strategy}`|`{:error, reason}`; `DBCleaner.clean()` → `:ok`|`{:error, reason}` (safe no-op if never started).
- **Approach**: State carried in **process dictionary** key `{DBCleaner, :state}` (no extra process). `:transaction` start calls `repo.begin_transaction()`, clean calls `repo.rollback()` (async: false only). `:truncation` start is no-op, clean issues `TRUNCATE #{table} RESTART IDENTITY CASCADE` per table via `repo.query!(repo, sql, [])`. Table names validated in start against allowlist regex `~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/` (SQL-injection guard since identifiers can't be parameterized); non-string/non-list raises `ArgumentError`. Unknown strategy → `{:error, msg}`.
- **Key invariants tested**: truncation start no-op; clean truncates all tables containing `TRUNCATE`/`RESTART IDENTITY`/`CASCADE`; empty tables → no queries; transaction start emits `{:begin}`, clean emits `{:rollback}` and no TRUNCATE; strategy state doesn't bleed between runs; behavioral isolation simulated with Agent "tables".
- **Variations**: none. **Subtasks**: none.
- **Notable**: Solution calls `repo.begin_transaction/0` and `repo.rollback/0` on the repo module directly (prompt mentioned `Ecto.Adapters.SQL.begin_transaction/1` "or equivalent"). test_harness `FakeRepo` Agent records `[{:query,sql}|{:begin}|{:rollback}]`. `async: false`.

### 074 — AssertHelpers (custom ExUnit assertion helpers)
- **Interface**: `use AssertHelpers` (imports macros). Three macros: `assert_changeset_error(changeset, field, message)` (exact string match on a field error); `assert_recent(datetime, tolerance_seconds \\ 5)` (DateTime/NaiveDateTime within tolerance of `DateTime.utc_now()`); `assert_eventually(func, timeout_ms \\ 1_000, interval_ms \\ 50)` (poll zero-arity fn until truthy or timeout).
- **Approach**: All are `defmacro` (so ExUnit reports correct file/line), all fail via `ExUnit.Assertions.flunk/1` with rich diagnostics. `assert_changeset_error` reads `changeset.errors` directly (NOT `Ecto.Changeset.traverse_errors/2`, which would crash on lightweight fakes) via `Keyword.get_values(field)` + maps `{msg,_opts}`; failure shows field errors or "no errors" + all_errors. `assert_recent` normalizes NaiveDateTime → `DateTime.from_naive!(ndt,"Etc/UTC")`, computes `abs(DateTime.diff(now,dt,:second))`, message shows actual/current/diff/tolerance. `assert_eventually` delegates to public `AssertHelpers.__poll__/4` (public so macro-generated code can call cross-module) computing `deadline = System.monotonic_time(:millisecond) + timeout_ms`.
- **Key invariants tested**: changeset pass/fail (multiple errors, no match, no field, empty); recent pass at boundary (-4s within 5), fail past/future, message includes "tolerance"; eventually passes immediately/before-timeout, returns truthy value, fails with "timed out"/"100", message includes last value (`:still_pending`) and elapsed/"ms".
- **Variations**: none. **Subtasks**: none.
- **Notable**: `__poll__` truthiness quirk — treats bare atoms (except `true`) as NOT-done so status atoms `:ok`/`:still_pending` keep polling while integers/tuples/lists count as done: `value != nil and value != false and (not is_atom(value) or value == true)`. Tests use `apply(DateTime,:utc_now,[])` to defeat the type checker narrowing branches. `async: true`.

### 075 — Generators (property-based test generators)
- **Interface** (all return `%StreamData{}`): `Generators.user()` (map `:id` pos_int, `:name` letters-only 1–50, `:email` `<local>@<domain>.<tld>`, `:age` 18–120, `:role` in `[:admin,:editor,:viewer]`); `Generators.money()` (`%{amount: 0..10_000_000, currency: one of USD/EUR/GBP/JPY/CHF}`); `Generators.date_range()` (`%{start_date, end_date}` Dates in 2000-01-01..2100-12-31, `start <= end`); `Generators.non_empty_list(generator)` (1–20 elements); `Generators.one_of_weighted([{weight, gen}])`.
- **Approach**: `alias StreamData, as: SD` (explicit-qualify, avoids bulk-import clashes). `user`/`money` via `SD.fixed_map`. `user_name` = `SD.bind(integer(1..50))` then fill exactly N codepoints from `member_of(?a..?z ++ ?A..?Z)` → structurally non-empty (no filter). `email`/`alnum_segment` similar with lowercase alnum. `date_range` works in gregorian days: binds `start_day`, then `SD.one_of([constant(start_day), integer(start_day..max_day)])` for `end_day` — explicit same-day branch guarantees `:eq` cases appear (not relying on probabilistic bias). `non_empty_list` = `bind(integer(1..20), &list_of(gen, length: &1))`. `one_of_weighted` = `Enum.flat_map` expanding each pair into `List.duplicate(gen, weight)` copies then `SD.one_of` (weight 0 → `[]` → never selected; propagates shrinking).
- **Key invariants tested**: all constraints hold without consumer filtering; role/currency diversity across 300 samples; date_range produces both `:eq` and `:lt` over 500 samples; list length 1–20 with min==1 and max>1; weighted 99:1 → ≥900/1000 common; weight 0 → never; composable with `StreamData.filter/map/list_of` and nesting `non_empty_list(one_of_weighted(...))`.
- **Variations**: none. **Subtasks**: none.
- **Notable**: Only family requiring an external dep (`stream_data` / `ExUnitProperties`). All constraints enforced generatively (no rejection sampling). `async: true`.

## Groups 076–080 — Classic Data Structures

Five self-contained classic data-structure tasks, each a single-shot `_01` (full solution + `test_harness.exs`), no variations and no fill-in-the-middle subtasks in this cluster. Common thread: all are **pure/persistent functional** implementations (explicit "no GenServer/ETS/process" in every prompt) using only the Elixir/Erlang stdlib, returning new values on every mutation; tests enforce immutability of the input value. No clocks, OTP, or external deps anywhere. Structs use `@enforce_keys`; augmentation/index tricks are used for asymptotic efficiency (max_finish augmentation, O(1) size counters, tuple-backed bit arrays). Task 076 uniquely ships a second, deliberately-broken model-generated solution alongside the reference.

### tasks/076_001_trie_01 — Trie (Prefix Tree)
- **Interface**: `Trie.new/0`, `insert(trie, word)`, `member?(trie, word)::bool`, `search(trie, prefix)::[String.t] (sorted)`, `delete(trie, word)`, `size(trie)::non_neg_integer`, `words(trie)::[String.t] (sorted)`. All `word`/`prefix` guarded `is_binary`.
- **Approach**: `%Trie{root, size}` struct; each node a plain map `%{children: %{grapheme => node}, end_of_word: boolean}`. Keys are `String.graphemes/1` (unicode-safe, not bytes). `size` stored on struct → O(1) `size/1`. `insert` no-ops (returns same trie, no size bump) if `word_exists?`. `search` = `descend` to prefix node then DFS `collect` + `Enum.sort`; `words` = collect from root with `""` acc. `delete` clears `end_of_word` and prunes dead-end leaf nodes on the way up (`not end_of_word and map_size(children)==0`), preserving shared-prefix nodes.
- **Key invariants tested**: exact-membership (prefix "hell" not member of "hello"; empty string not a member); duplicate insert doesn't grow size; delete of prefix word ("car") leaves longer word ("card") and vice versa; delete non-existent / delete-from-empty are no-ops; original trie unchanged after insert/delete; 100-word scale test (`word001..word100`, `search("word0")` returns 99).
- **Variations**: none. **Subtasks**: none.
- **Notable**: Ships an **alternative model-generated solution** `solution_Qwen3.5-4B-Q6_K_gguf.ex` (Qwen3.5-4B Q6_K gguf) that is clearly **broken** — uses `children: nil` sentinel instead of struct, `insert/build_node` recurse incorrectly, `delete_char` has an illegal `Map.delete(...) |> cond do ...` pipe into `cond`, `words/2` references an undefined `trie` var, would not compile/pass. Reference solution is idiomatic and correct.

### tasks/077_001_interval_tree_for_overlapping_range_queries_01 — Interval Tree
- **Interface**: `IntervalTree.new/0` (returns `nil`), `insert(tree, {start, finish})`, `overlapping(tree, {start, finish})::[interval]`, `enclosing(tree, point::integer)::[interval]`. Interval = `{integer, integer}`, `start <= finish` guaranteed by caller.
- **Approach**: Augmented **AVL tree**; node = map `%{interval, max_finish, height, left, right}`, empty tree = `nil`. BST-keyed on `start` (`s <= ns` goes left). `make_node/3` recomputes `height` and `max_finish` (max finish over subtree) bottom-up; full AVL rebalance (`rotate_left/right`, `balance_factor`, LL/LR/RL/RR cases) on every insert → O(log n). Queries use accumulator-passing DFS with two prune rules: (1) skip subtree when `max_finish < qs`/`point`; (2) skip right subtree when node `start > qf`/`point`. Overlap predicate `s <= qf and f >= qs` (touching endpoints count).
- **Key invariants tested**: empty tree → `[]`; touching intervals overlap (`{1,5}`&`{5,10}` both match query `{5,5}`); degenerate `{4,4}` point intervals; `enclosing` returns all containing intervals; **duplicate intervals stored and both returned**; persistence (t0/t1/t2 independent); 200-interval scale test with 3-hit range query and single-hit point query. Tests use unordered membership (`in`, `length`) since results aren't sorted.
- **Variations**: none. **Subtasks**: none.
- **Notable**: Result lists are unsorted (accumulator order); doctests in `@moduledoc` sort explicitly. Correct AVL augmentation maintenance through rotations is the tricky part.

### tasks/078_001_ring_buffer_01 — Ring Buffer (Circular Buffer)
- **Interface**: `RingBuffer.new(capacity)` (guard `is_integer and > 0`), `push(buffer, item)`, `to_list(buffer)::list (oldest→newest)`, `size(buffer)::0..capacity`, `peek_oldest(buffer)::{:ok, item}|:error`, `peek_newest(buffer)::{:ok, item}|:error`.
- **Approach**: `%RingBuffer{capacity, store, read, write, size}` struct. Prompt **mandates a fixed-size tuple** backing store (`:erlang.make_tuple(capacity, nil)`), 1-based access via `:erlang.element/setelement` (offset +1), integer `read`/`write` head indices wrapping via `rem(_, cap)` — explicitly forbids list/`Enum`-grown store. `push` writes at `write`, advances `write`; when full (`size == cap`) also advances `read` (overwrite oldest, size pinned at cap), else bumps `size`. `to_list` maps `size` offsets from `read` with wraparound. `peek_newest` index = `rem(write - 1 + cap, cap)`.
- **Key invariants tested**: empty → `:error`/`[]`/size 0; size grows to and caps at capacity; oldest overwritten on overflow (`push 1..4` cap 3 → `[2,3,4]`); 20-push-into-cap-4 keeps `[17,18,19,20]`; capacity-1 buffer; mixed value types (ints, strings, atoms, tuples, lists).
- **Variations**: none. **Subtasks**: none.
- **Notable**: FIFO overwrite semantics (not error-on-full). `nil` sentinel in unused slots (fine since `size` bounds reads).

### tasks/079_001_bloom_filter_01 — Bloom Filter
- **Interface**: `BloomFilter.new(expected_size, false_positive_rate)` (guards: `expected_size` positive int; rate `is_float`, `0.0 < p < 1.0`), `add(filter, item)::t`, `member?(filter, item)::bool`, `merge(filter1, filter2)::t` (raises `ArgumentError` on differing `m`/`k`).
- **Approach**: `%BloomFilter{m, k, bits}` struct. Optimal params: `m = ceil(-n*ln(p)/ln(2)^2)`, `k = max(1, round(m/n*ln2))` with `@ln2 :math.log(2)` module attr. `bits` = tuple of 64-bit-word integers (`Tuple.duplicate(0, ceil(m/64))`), bit ops via `Bitwise` (`bor/bsl/bsr/band`), word index `div(_,64)`, offset `rem(_,64)`, `put_elem`/`elem` for O(1) word access. `k` independent hashes derived from one primitive: `:erlang.phash2({seed, item}, m)` for `seed <- 0..k-1`. `add` folds set_bit over seeds; `member?` = `Enum.all?` bits set; `merge` zips both tuples word-wise with `bor` (second `merge/2` clause raises).
- **Key invariants tested**: computed `m,k > 0`; tighter p → larger m; larger n → larger m; **no false negatives** (500 items, and atoms/ints/tuples/`{"hello",:world}`); empirical false-positive rate `< 2*p` (n=1000, p=0.03); empty filter no members; merge union membership; merge raises on mismatched params; merge with empty is identity; **merge commutative → identical `bits`**; add idempotent (bits unchanged on re-add).
- **Variations**: none. **Subtasks**: none.
- **Notable**: `phash2/2` seeding-by-tuple is the prescribed trick for k independent hashes; probabilistic FP test relies on `phash2` determinism.

### tasks/080_001_directed_acyclic_graph_with_topological_sort_01 — DAG with Topological Sort
- **Interface**: `DAG.new/0`, `add_vertex(dag, vertex)::t` (idempotent), `add_edge(dag, from, to)::{:ok, t}|{:error, :cycle}`, `topological_sort(dag)::{:ok, [vertex]}`, `predecessors(dag, vertex)::[vertex]`, `successors(dag, vertex)::[vertex]`. Vertices = any term.
- **Approach**: `%DAG{vertices: MapSet, out_edges: %{v=>MapSet}, in_edges: %{v=>MapSet}}` — forward + reverse adjacency both maintained. `add_edge` uses `with` chain: `require_vertex` (both must exist, else `{:error, :vertex_not_found}`) → `check_no_cycle` → commit via `Map.update!` on both edge maps. **Eager cycle detection** (prompt-mandated): self-loop rejected explicitly; otherwise iterative-DFS `dfs_reaches?(out_edges, to, from)` — cycle iff `from` reachable from `to`. `topological_sort` = **Kahn's algorithm**: build in-degree map from `in_edges` sizes, seed queue with zero-in-degree vertices sorted for determinism, `kahn/4` decrements successor in-degrees, appends newly-zero vertices `Enum.sort`ed → deterministic ordering.
- **Key invariants tested**: empty → `{:ok, []}`; duplicate `add_vertex` ignored; direct/self/indirect cycles rejected; linear chain gives exact `[:a,:b,:c]`; diamond and known dep graph (mix→hex→ssl→crypto/public_key) validated via helper `valid_topological_order?` (from-before-to index check); isolated vertices included; predecessors/successors direct-neighbor correctness and mutual consistency.
- **Variations**: none. **Subtasks**: none.
- **Notable**: Determinism via sorting zero-in-degree frontier (so linear chain yields the exact expected order, not just any valid one); prompt explicitly requires DFS cycle detection + Kahn's for sort (both implemented). Iterative (explicit-stack) DFS to avoid deep-graph stack overflow.

## Groups 086–101 — Business Logic & Security

Eight independent single-file Elixir modules exercising business-rules and application-security patterns: e-commerce pricing, RBAC, input sanitization/XSS/SQLi/path-traversal defense, password policy, HMAC-signed tokens, PII log-masking, RFC-6238 TOTP, and a rate-limiting sliding-window counter. Mostly pure data/functional modules (086, 087, 096, 097, 099, 100); two are OTP-based (098 test uses an Agent clock, 101 is a GenServer). Determinism for time-sensitive code is achieved by injecting a `:clock` zero-arity function (098, 100 via `:time` opt, 101). Every family has ONLY the `_01` single-shot directory — no `b=02+` problem variations and no `d=02+` fill-in-the-middle subtasks exist in this cluster. All standard-library only, no external deps.

### 086_001 — Shopping Cart with Price Calculations
- **Interface**: `Cart.new(opts \\ [])` (`:tax_rate` float, default `0.0`); `Cart.add_item(cart, product_id, quantity, unit_price) :: {:ok, cart} | {:error, :invalid_quantity}`; `Cart.remove_item(cart, product_id) :: cart` (no-op if absent); `Cart.update_quantity(cart, product_id, quantity) :: {:ok, cart} | {:error, :not_found | :invalid_quantity}`; `Cart.calculate_totals(cart) :: %{subtotal, tax, grand_total, items}`.
- **Approach**: Pure structs, no OTP/DB. `%Cart{tax_rate, items: %{product_id => %Cart.Item{}}}`; nested `Cart.Item` struct `[:product_id, :quantity, :unit_price, discount_rate: 0.0]` with `@enforce_keys`. `add_item` uses `Map.update/4` (accumulates qty; **first price wins**, stored unit_price unchanged on re-add). Totals computed by mapping `build_item_summary/1` over `Map.values`.
- **Key invariants tested**: bulk discount = 10% off unit_price when `quantity >= 10` (module attrs `@bulk_discount_threshold 10`, `@bulk_discount_rate 0.10`); discount is **per-line-item, not per-cart**; `line_total = unit_price * (1 - discount_rate) * quantity`; tax applied on **discounted** subtotal (`subtotal * tax_rate`); `update_quantity` to 0 removes item; zero/negative qty rejected; empty cart → all zeros. Uses `assert_in_delta` for float math.
- **Variations**: none. **Subtasks**: none.
- **Notable**: All monetary values floats; qty=9 vs qty=10 boundary explicitly tested. ExUnit `async: true`.

### 087_001 — Permission System with Role-Based Access
- **Interface**: `Permissions.can?(role, resource, action, rules) :: boolean` (delegates to arity-5 with `[]`); `Permissions.can?(role, resource, action, rules, opts) :: boolean`.
- **Approach**: Role ranks via `@role_rank %{viewer: 0, editor: 1, manager: 2, admin: 3}`. `rules :: %{resource => %{action => required_role | :owner}}`. Uses `with` chain `fetch_resource → fetch_action → check`; unknown resource/action returns `:error` → `false` (never raises). `check/3` has three clauses: `:owner` (identity check), normal role (guarded `rank(role) >= rank(required_role)`), catch-all deny.
- **Key invariants tested**: higher role inherits all lower-role permissions (monotonic hierarchy — property test iterates adjacent role pairs); `:owner` rule is identity-based, role-**irrelevant** — grants iff `owner_id == user_id` (both non-nil), so even `:admin` denied on id mismatch, `:viewer` granted on match; missing owner opts → deny; unknown resource/action → false.
- **Variations**: none. **Subtasks**: none.
- **Notable**: `:owner` composable alongside role-gated actions on same resource. ExUnit `async: true`.

### 096_001 — Input Sanitizer Module
- **Interface**: `Sanitizer.html(input, opts \\ [])` (`:allow` allowlist, default `~w[b i em strong a]`); `Sanitizer.sql_identifier(input) :: {:ok, String.t()} | {:error, :empty}`; `Sanitizer.filename(input) :: {:ok, String.t()} | {:error, :empty}`.
- **Approach**: HTML in two phases: (1) `strip_raw_content_tags/1` regex (caseless+dotall) nukes `script|style|noscript|iframe` **with inner content**; (2) hand-rolled single-pass char-by-char state machine (`:text`/`:tag` states, iodata accumulator) — no external HTML parser. Allowlisted tags rebuilt attribute-free except `href` on `<a>`; disallowed tags stripped but inner text kept. `poisoned_a` boolean state suppresses both the opening and matching `</a>` when href is a `javascript:` URI (checked by stripping `\x00-\x20` then case-insensitive `starts_with?("javascript:")`). `href` extraction handles double/single/unquoted via 3 regexes; values HTML-escaped. `sql_identifier` strips `[^a-zA-Z0-9_]`, prepends `_` if leading digit, `{:error, :empty}` if blank. `filename` strips null bytes, `/`, `\`, non-`[a-zA-Z0-9_\-.]`, collapses `\.{2,}` → `.`, trims leading/trailing dots.
- **Key invariants tested**: tag case normalized to lowercase (`<B>`→`<b>`); XSS vectors (`onerror`, `onclick`) stripped; `javascript:` (any case + leading whitespace) neutralized keeping inner text; custom `:allow` respected; SQLi payload `col' OR '1'='1` → `colOR11`; traversal `../../etc/passwd` → `etcpasswd`, Windows `..\Windows\System32` sanitized.
- **Variations**: none. **Subtasks**: none.
- **Notable**: Slashes stripped (not converted), so path segments concatenate directly. ExUnit `async: true`.

### 097_001 — Password Policy Enforcer
- **Interface**: single public `PasswordPolicy.validate(password, context) :: :ok | {:error, [atom()]}`; also public `levenshtein(a, b)` (marked `@doc false`). Raises `ArgumentError` if `context` lacks `:username`.
- **Approach**: `build_config/1` merges context over 10 module-attr defaults (`min_length 8`, `max_length 128`, `require_*` all `true`, `common_passwords []`, `previous_passwords []`, `max_username_similarity 3`). Runs a **list of 9 check closures** (`&check_min_length/2` … `&check_username_similarity/2`) via `Enum.reduce`, collecting **all** violations (reversed to preserve rule-evaluation order). Self-implemented Levenshtein: iterative two-row DP over `String.graphemes` (Unicode-safe), O(m·n) time / O(min) space, swaps to keep shorter string as columns.
- **Key invariants tested**: all violations reported not just first; violation atoms `:too_short, :too_long, :no_uppercase, :no_lowercase, :no_digit, :no_special, :common_password, :reused_password, :too_similar_to_username`; special = `[^a-zA-Z0-9]`; common-password match case-insensitive; reuse match exact; similarity rejects when `distance <= threshold` (identical password → distance 0 → rejected); toggling `require_*: false` skips that check.
- **Variations**: none. **Subtasks**: none.
- **Notable**: test_harness.exs is NOT ExUnit — a **hand-rolled `PasswordPolicyTest.run/0`** framework printing `✓/✗` and calling `System.halt(1)` on failure (uses `MapSet.subset?`/`equal?` for order-independent multi-violation asserts).

### 098_001 — Token Generator and Validator
- **Interface**: `SecureToken.generate(payload, secret, ttl_seconds, opts \\ []) :: token` (guards `is_binary(secret)`, `ttl_seconds > 0`); `SecureToken.verify(token, secret, opts \\ []) :: {:ok, term} | {:error, :expired | :invalid_signature | :malformed}`. `opts` only key is `:clock` (zero-arity → Unix seconds; default `System.os_time(:second)`).
- **Approach**: Stateless HMAC-SHA256 tokens. Wire format `<<issued_at::signed-64, expires_at::signed-64, payload_size::unsigned-32, payload::binary, mac::binary-32>>` where payload = `:erlang.term_to_binary/1`, then `Base.url_encode64(_, padding: false)`. MAC via `:crypto.mac(:hmac, :sha256, secret, data)` over the length-prefixed data region. `verify` is a strict `with` pipeline: `decode_base64 → split_mac (trailing 32B) → parse_data (structural, guard `byte_size(rest) == payload_size`) → verify_mac → check_expiry → decode_payload`. Constant-time MAC compare via `bor`/`bxor` fold (`import Bitwise`). Deserialize with `:erlang.binary_to_term(bytes, [:safe])` rescuing `ArgumentError`.
- **Key invariants tested**: exact error precedence — any pre-HMAC failure = `:malformed`, HMAC mismatch = `:invalid_signature` (**takes precedence over expiry** even for expired tokens with wrong secret), post-HMAC expiry = `:expired`, post-HMAC deserialize failure = `:malformed`; **strict `<`** expiry so `now == expires_at` is already expired (at exact ttl boundary); URL-safe output (no `+`/`/`/`=`); cross-secret non-verifiability; arbitrary payload types (atom/int/list/nested map) round-trip.
- **Variations**: none. **Subtasks**: none.
- **Notable**: Clock injected for deterministic expiry. Test uses `use ExUnit.Case, async: false` + `defmodule Clock` (Agent) started via `start_supervised!({Clock, 1_000_000})`, wrapping generate/verify with `clock: &Clock.now/0`.

### 099_001 — Data Masking for Logs
- **Interface**: `LogMasker.new(sensitive_keys) :: t()` (opaque `%LogMasker{sensitive_keys: MapSet}`); `LogMasker.mask(masker, data) :: term` (map/keyword-list/string/nested); `LogMasker.mask_string(masker, string) :: String.t()`.
- **Approach**: `new/1` normalizes keys (`normalize_key` downcases atom/string → String) into a MapSet. `do_mask` recursion: plain maps (`is_map and not is_struct`) via `Map.new`, lists distinguish keyword-list (`keyword_list?` all `{atom,_}`) from plain lists, strings routed through `mask_string`, everything else (structs/numbers/atoms/tuples) untouched. Sensitive key → value replaced with `"[MASKED]"` regardless of type. `mask_string` applies 3 regexes in order: credit-card (`\b\d(?:[\s-]?\d){12,18}\b`, 13–19 digits) masking all but last 4 with `*` keeping separators (`mask_cc_match` walks graphemes counting digits); SSN (`\b\d{3}-\d{2}-\d{4}\b` → `***-**-****`); email (`([local])@([domain])` → first char + `***@domain`).
- **Key invariants tested**: case-insensitive key matching for atom AND string keys; recursive nested maps / lists-of-maps / keyword lists; non-sensitive keys preserved but their **string values still pattern-masked** (embedded SSN/email/CC scrubbed everywhere); non-string sensitive values (int/nil/list) → `[MASKED]`; empty masker masks structurally nothing but still pattern-masks strings; CC last-4 preserved with dash/space/no separators.
- **Variations**: none. **Subtasks**: none.
- **Notable**: `@opaque t`; `mask_string` order is CC→SSN→email (SSN before email to avoid interference). ExUnit `async: true`.

### 100_001 — TOTP (Time-Based One-Time Password)
- **Interface**: `TOTP.generate_secret() :: String.t()` (base32, 160-bit/20-byte, unpadded); `TOTP.generate_code(secret, time \\ :os.system_time(:second)) :: String.t()` (6-digit zero-padded); `TOTP.valid?(secret, code, opts \\ []) :: boolean` (`:time` default now, `:window` default 1 step each direction); `TOTP.provisioning_uri(secret, issuer, account_name) :: String.t()`.
- **Approach**: RFC 6238, `@period 30`, `@digits 6`, `@secret_bytes 20`. `generate_secret` = `:crypto.strong_rand_bytes(20)` → self-implemented base32. `generate_code`: `step = div(time, 30)`, `<<step::big-unsigned-integer-size(64)>>`, `:crypto.mac(:hmac, :sha, key, counter)`, RFC-4226 dynamic truncation (`offset = last_byte &&& 0x0F`, read 4 bytes, `&&& 0x7F` top bit), `rem 1_000_000`, `String.pad_leading(6, "0")`. `valid?` iterates `-window..window` steps with constant-time `secure_equal?` compare; `normalize_code` accepts int or string. Self-implemented RFC-4648 base32 encode (5-byte→8-char groups, bit-padded tail) / decode (5-bit chunks). `provisioning_uri` builds `otpauth://totp/<issuer:account>?...` with `URI.encode`/`URI.encode_query`, params `secret, issuer, algorithm=SHA1, digits=6, period=30`.
- **Key invariants tested**: **canonical RFC 6238 test vectors** (secret `GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ`): t=59→`287082`, t=1111111109→`081804`, t=1111111111→`050471`, t=1234567890→`005924` (leading-zero case), t=2000000000→`279037`, t=20000000000→`353130`; secret matches `[A-Z2-7]+`, unique per call; code stable across the 30s step, changes at boundary; window drift ±1 step accepted, ±2 rejected unless `window: 2`, `window: 0` exact-only; URI parseable with `URI.parse`, special chars encoded.
- **Variations**: none. **Subtasks**: none.
- **Notable**: `time` param is the injectable clock (no separate opt); `import Bitwise`. ExUnit `async: true`; vectors generated at compile time via a `for` comprehension emitting tests.

### 101_001 — Sliding Window Counter
- **Interface**: `SlidingCounter.start_link(opts) :: GenServer.on_start` (`:clock` zero-arity ms, default `System.monotonic_time(:millisecond)`; `:bucket_ms` default `1_000`; `:max_window_ms` default `bucket_ms * 60`; `:cleanup_interval_ms` default `60_000`, `:infinity` disables; `:name`); `SlidingCounter.increment(server, key) :: :ok`; `SlidingCounter.count(server, key, window_ms) :: non_neg_integer`.
- **Approach**: GenServer, state `%{clock, bucket_ms, max_window_ms, cleanup_interval_ms, keys: %{key => %{bucket_index => count}}}`. `start_link` uses `Keyword.split(opts, [:name])` to separate GenServer opts. `bucket_for = Integer.floor_div(timestamp_ms, bucket_ms)`. **increment is a `call`** (not cast) so timestamp is read before returning — deterministic under manual clock advance. `count`: computes `min_bucket = -Integer.floor_div(-(now - window_ms), bucket_ms)` (ceiling div) and sums counts of buckets `b >= min_bucket` — **bucket-start-in-window** semantics (stricter than mere overlap). Cleanup via `Process.send_after(self(), :cleanup, interval)`, rescheduled after each run; `handle_info(:cleanup, ...)` also directly triggerable for synchronous tests; `do_cleanup` drops buckets/keys with start before `now - max_window_ms` (`Map.filter`, empty inner map → whole key removed). Catch-all `handle_info(_msg, state)` ignores stray messages.
- **Key invariants tested**: zero for unseen key; events outside `[now-window_ms, now]` excluded (`advance(1001)`→0, `advance(999)`→still counted); per-key independence and independent expiry; after cleanup `map_size(state.keys) == 0` when all expired (probed via `:sys.get_state`), active keys survive; `window_ms < bucket_ms` works; very large window (86_400_000) includes all; ceiling-div boundary semantics ("event at T in window iff T >= now - window_ms").
- **Variations**: none. **Subtasks**: none.
- **Notable**: `@default_max_window_buckets 60` (60× bucket_ms) chosen so tests can actually evict without hours of clock advance. ExUnit `async: false` with Agent-based `Clock` (`start_supervised!({Clock, 0})`, `clock: &Clock.now/0`, `bucket_ms: 100`, `cleanup_interval_ms: :infinity`).

## Groups 623–626 — Mini Real-World Systems

Four self-contained "mini clone" tasks, each a single GenServer that reimplements the core data model of a well-known infrastructure system in pure OTP (no external deps, single file). Every family is a single `_01` full single-shot task with `prompt.md` + `solution.ex` + `test_harness.exs` — there are **no `b=02+` variations and no `d=02+` fill-in-the-middle subtasks** in this cluster (glob `tasks/623_* … 626_*` returns exactly four dirs). Common thread: content/data-addressable storage, deterministic serialization or scoring, and ExUnit harnesses that assert exact structural results; two families (S3, TSDB) exercise real side effects (filesystem persistence, injected clock + `Process.send_after` cleanup).

### 623_001 — Mini Elasticsearch-like Inverted Index (`InvertedIndex`)
- **Interface**: `start_link(opts)` (opts `:name`, `:stop_words` MapSet); `index(server, id, fields, opts \\ [])` (fields = `%{field => text}`, opts `:stem`) → `:ok`; `remove(server, id)` → `:ok` (no-op if absent); `search(server, query, opts \\ [])` (opts `:boosts` map `%{field => n}`, `:limit`, `:stem`) → `[%{id:, score:}]` desc; `suggest(server, prefix, limit \\ 10)` → `[String.t()]`; `stats(server)` → `%{document_count:, term_count:}`.
- **Approach**: GenServer, plain-map state: `docs: %{id => %{field => [token]}}`, `postings: %{term => %{id => %{field => count}}}`, `doc_freq: %{term => count}`. Tokenize = `String.downcase |> String.split(~r/[^a-z0-9]+/, trim: true) |> reject stop_words |> optional stem`. TF-IDF: `tf = count/total_tokens_in_field`, `idf = :math.log(total_docs/df)`; per term summed over fields as `tf*idf*boost` (default boost 1), summed across query terms. Re-index calls `do_remove` first to keep counts consistent. `suggest` filters `doc_freq` keys by prefix, sorts by df desc.
- **Key invariants tested**: higher TF ranks first; rarer term → higher IDF can outscore common term; stop words unsearchable; custom stop_words replace defaults ("the" then indexable); `title` boost reorders; term in 2 fields > 1 field; `limit` caps; removal decrements doc count + purges postings; re-index replaces cleanly (old terms gone, count stays 1); suggest sorted by df, respects limit, case-insensitive, empty on miss; punctuation stripped; `:name` registration.
- **Variations**: none. **Subtasks**: none.
- **Notable**: `stem/1` and `tokenize/3` are public (`@doc false`) — caller must keep index/search stem flags consistent (stemmed index + unstemmed query → no match, asserted). Stemmer strips (in order) `tion→t, ment, ing, er, ly, ed, s` with a "root ≥ 2 chars" guard, plus an **undocumented** `dedup_trailing_consonant/1` (drops doubled final consonant). Scores are raw floats, not normalized. Default 33-word stop list hardcoded as `@default_stop_words`.

### 624_001 — Mini Git-like Object Store (`ObjectStore`)
- **Interface**: `start_link(opts)` (`:name`); `store(server, content)` → `{:ok, hash}` (idempotent); `retrieve(server, hash)` → `{:ok, content} | {:error, :not_found}`; `tree(server, entries)` (entries = `%{name:, hash:, type: :blob|:tree}`) → `{:ok, tree_hash}`; `commit(server, tree_hash, parent_hash | nil, message, author)` → `{:ok, commit_hash}`; `log(server, commit_hash)` → `{:ok, [%{hash:, message:, author:, tree:, parent:}]}` newest→oldest | `{:error, :not_found}`.
- **Approach**: GenServer state is a single flat map `%{sha1_hex => raw_binary}` — no type tag at storage layer. Hash = `:crypto.hash(:sha, content) |> Base.encode16(case: :lower)` (40-char). `do_store` uses `Map.put_new` (dedup). Tree serialization: `Enum.sort_by(&.name)` then `map_join("\n", "type hash name")` — order-independent hash. Commit serialization fixed order: `"tree H\nparent P\nauthor A\nmessage M"` where nil parent → literal `"nil"`. `log` recursively walks parent via `parse_commit` (`String.split("\n", parts: 4)` so message may contain newlines) + `strip_prefix`.
- **Key invariants tested**: hash matches `:crypto` SHA-1; dedup returns same hash; tree hash independent of entry order but sensitive to content; empty tree/empty content OK; binary/null-byte content roundtrips; commit deterministic for same metadata; multi-line/special-char messages preserved; log walks 3-commit chain newest→oldest with correct parents; unknown start hash → `:not_found`; full blobs→trees→commits→log workflow with every object retrievable.
- **Variations**: none. **Subtasks**: none.
- **Notable**: `walk_log` distinguishes a missing **start** commit (`{:error, :not_found}`) from a **dangling parent** mid-chain (stops gracefully, returns partial log). Serialization is human-readable text, not Git's real `type size\0` header + zlib — a deliberate simplification. `store/2` and `retrieve/2` have `is_binary` guards.

### 625_001 — Mini S3-like Object Storage (`ObjectStorage`)
- **Interface**: `start_link(opts)` (`:root_dir` default `"./object_storage_data"`, `:name`); `create_bucket/2` → `:ok | {:error, :already_exists | :invalid_name}`; `delete_bucket/2` → `:ok | {:error, :not_found | :not_empty}`; `list_buckets/1` → `{:ok, sorted names}`; `put_object(server, bucket, key, data, content_type \\ "application/octet-stream", metadata \\ %{})` → `:ok | {:error, :bucket_not_found}`; `get_object/3` → `{:ok, %{data:, content_type:, metadata:, size:, last_modified: DateTime}} | {:error, :bucket_not_found | :not_found}`; `delete_object/3` (idempotent) → `:ok | {:error, :bucket_not_found}`; `list_objects(server, bucket, opts)` (`:prefix` "", `:max_keys` 1000) → `{:ok, [%{key:, size:, last_modified:}]}` sorted; `copy_object/5` → `:ok | {:error, :src_bucket_not_found | :dst_bucket_not_found | :not_found}`; multipart: `start_multipart/5` → `{:ok, upload_id}`, `upload_part(server, upload_id, part_number, data)`, `complete_multipart/2` (`:no_parts` if empty), `abort_multipart/2`.
- **Approach**: GenServer, **filesystem-backed** at `root_dir/buckets/<name>/objects/`. Object key url-safe-encoded via `:erlang.term_to_binary(key) |> Base.url_encode64(padding: false)`; each object = `<enc>.data` (raw) + `<enc>.meta` (`:erlang.term_to_binary(%{content_type, metadata, size, last_modified})`). No in-memory bucket/object index — every call hits `File.dir?`/`File.ls!`/`File.read!`. Bucket name validated by `~r/\A[a-z0-9.\-]+\z/` (non-empty). `list_objects` reads `.meta` filenames, decodes keys, filters by prefix, sorts, `take(max_keys)`. Multipart state is **in-memory only** (`state.multipart_uploads: %{upload_id => %{bucket, key, content_type, metadata, parts: %{part_num => data}}}`); `complete` sorts parts by number, `IO.iodata_to_binary`, writes object, deletes upload_id. `upload_id = :crypto.strong_rand_bytes(16) |> Base.url_encode64`.
- **Key invariants tested**: bucket CRUD + validation (rejects "", UPPER, spaces, underscore; allows hyphens/dots/digits); delete non-empty → `:not_empty`; put overwrites silently; default content_type; 4 KB random binary roundtrip; prefix + max_keys listing; copy within/across buckets, same-key no-op, all 3 copy error paths; multipart out-of-order + same-part overwrite + `:no_parts` + invalidation after complete/abort; **objects survive `GenServer.stop` + restart with same root_dir** (metadata too); concurrent multipart uploads isolated.
- **Variations**: none. **Subtasks**: none.
- **Notable**: harness uses `@moduletag :tmp_dir` (ExUnit auto per-test temp dir). Persistence is the differentiator — durability comes for free from the filesystem layout; multipart deliberately does NOT survive restart. `delete_object` on a missing bucket errors, but on a missing key succeeds (idempotent `File.rm` ignores result).

### 626_001 — Mini Prometheus-like Time-Series DB (`TSDB`)
- **Interface**: `start_link(opts)` (`:chunk_duration_ms` 60_000, `:retention_ms` 3_600_000, `:cleanup_interval_ms` 60_000 or `:infinity`, `:clock` zero-arity ms fn default `fn -> System.monotonic_time(:millisecond) end`, `:name`); `insert(server, metric_name, labels, timestamp, value)` → `:ok` (**GenServer.cast**); `query(server, metric_name, label_matchers, {start_ts, end_ts})` → `[{labels_map, [{ts, value}]}]`; `query_agg(server, metric, matchers, {start_ts, end_ts}, aggregation, step_ms)` (`aggregation ∈ :avg | :sum | :max | :rate`) → `[{labels, [{window_start, agg_value}]}]`.
- **Approach**: pure GenServer (no ETS, no child processes). State `series: %{{metric_name, sorted_labels} => %{chunk_start => [sorted {ts, value}]}}`. `sorted_labels = Enum.sort(Map.to_list(labels))` so label order can't fork a series. `chunk_start = div(timestamp, chunk_duration_ms) * chunk_duration_ms`. `insert_sorted/2` keeps each chunk ascending by ts (dup ts appended after). `do_query` narrows to chunks in `[chunk_start_for(start), chunk_start_for(end)]`, flattens, filters `start_ts <= ts <= end_ts` **inclusive**, sorts. `labels_match?` = all matcher pairs present (empty map matches all; superset labels allowed). Aggregation windows are **half-open** `[start, end)` stepped by `step_ms` (`Stream.iterate |> take_while(< end_ts)`); empty windows (and `<2` points for `:rate`) omitted. `:rate = (last_v - first_v) / ((last_ts - first_ts)/1000)`.
- **Key invariants tested**: out-of-order inserts sorted; inclusive time filter; label subset matching + empty-matcher-matches-all + label-order dedup; multi-chunk span + sub-range chunk pruning; `:sum/:avg/:max/:rate` exact values; rate omits <2-pt windows; empty windows omitted; per-series separate aggregations; boundary point `t=1000` lands in chunk 1000 not 0; **cleanup** removes chunks where `chunk_start + chunk_duration_ms <= now - retention_ms` and drops emptied series.
- **Variations**: none. **Subtasks**: none.
- **Notable**: `insert` is async `cast` — determinism relies on later sync `call`s (query) draining the mailbox. **Injected clock**: harness uses an Agent-based `Clock` (`now/advance/set`, registered by module name); cleanup is triggered manually via `send(db, :cleanup)` then `:sys.get_state(db)` to force synchronous processing (tests set `cleanup_interval_ms: :infinity`, `chunk_duration_ms: 1_000`, `retention_ms: 10_000`). `schedule_cleanup` uses `Process.send_after(self(), :cleanup, interval)`, no-op on `:infinity`. Subtle boundary asymmetry to note: `query` bounds inclusive, `query_agg` windows half-open.

## tasks_multifile/ — Phoenix/Ecto Multi-File Tasks

Eleven multi-file backend tasks. Unlike other clusters these dirs are **flat** — no `_b` variations, no `_d` fill-in-the-middle subtasks; each dir is one whole-app task with `prompt.md` + `test_harness.exs` (an ExUnit file), and the reference `solution.ex` bundles every module inline via `<file path="...">…</file>` blocks. Common thread: build a small but complete Elixir web/back-end feature (Phoenix+Ecto JSON API, or bare `Plug`+`Jason`, or pure OTP GenServer) exercising real-world API concerns — pagination, filtering, soft-delete, bulk/partial writes, uploads, versioning, authz, idempotency, HMAC webhooks, long-polling, persisted state machines. **Solved (have solution.ex): 016, 017, 018, 102. Unsolved (prompt + test_harness only): 019–025** — for those the interface/behavior below is reconstructed from the prompt and the enforced tests. Every task forbids external libs beyond Phoenix/Ecto or Plug/Jason (+`:crypto`); several inject a clock or fake repo for determinism.

### 016 paginated_list_endpoint — Offset Pagination (SOLVED)
- **Interface**: `PaginatedList.Items.list_items(params \\ %{})` → `%{data: [Item], meta: %{current_page, page_size, total_count, total_pages}}`; controller `PaginatedListWeb.ItemController.index/2` renders via `Phoenix.Controller.json/2`; route `get "/items"` under `/api`. Schema `PaginatedList.Item` (`items` table, `:name` string + `timestamps(type: :utc_datetime_usec)`).
- **Approach**: string params `"page"`/`"page_size"` parsed with `Integer.parse` (guards `n >= 1`); defaults page=1, size=20, `@max_page_size 100` via `min/2`; `offset = (page-1)*page_size`; base query `order_by: [asc: i.inserted_at, asc: i.id]` for determinism; `Repo.aggregate(:count, :id)` for total; `compute_total_pages(0,_) → 0` else `ceil(total/size)`. Serializes `inserted_at` with `DateTime.to_iso8601/1`. Migration adds composite index `[:inserted_at, :id]`.
- **Key invariants tested**: default page 20; clamp size>100→100; page/size ≤0 or non-numeric → defaults; page beyond total → empty `data` but correct meta; empty DB → total_pages 0; exact vs non-exact division rounding; page-2 disjoint from page-1.
- **Notable**: test seeds via `Repo.insert_all(returning: true)` with monotonically increasing `inserted_at`.

### 017 search_endpoint_with_filtering_and_sorting — Search/Filter/Sort (SOLVED)
- **Interface**: `MyApp.Products.list_products(params)` → `{:ok, [Product]} | {:error, :invalid_sort_field}`; `MyAppWeb.ProductController.index/2` → `MyAppWeb.ProductJSON.index/1` (`%{data: [...]}`); route `get "/products"`. Schema `MyApp.Products.Product` fields `name`/`category`/`price` (`:decimal`, migration col `:numeric`).
- **Approach**: single composable Ecto query piped through `filter_by_name` (ILIKE `"%name%"`), `filter_by_category` (exact `==`), `filter_by_min_price`/`filter_by_max_price` (`Decimal.parse`, `>=`/`<=`), `apply_sorting`. **Security**: `@allowed_sort_fields ~w(name price category)` allowlist; invalid `sort` → `{:error, :invalid_sort_field}` → HTTP 400 `{"error":"invalid sort field"}`; validated field converted via `String.to_existing_atom` and used with `order_by([p],[{^direction, field(p, ^atom)}])`. `order` defaults `:asc`, ignored if no `sort`. Price serialized as string via `Decimal.to_string`.
- **Key invariants tested**: case-insensitive partial name; exact category; inclusive price bounds (incl. min==max); combined filters; SQL-injection sort strings return 400 and leave table intact; `order` w/o `sort` → 200 all rows; price is string.
- **Notable**: all filtering/sorting at DB level, single round-trip; uses `~p"/api/products"` verified routes in tests.

### 018 crud_with_soft_delete — CRUD + Soft Delete (SOLVED)
- **Interface** (`SoftCrud.Documents` context): `list_documents(opts \\ [])`, `get_document(id, opts \\ [])`→`{:ok,doc}|{:error,:not_found}`, `create_document/1`, `update_document/2`, `soft_delete_document/1`, `restore_document/1`; all respect `include_deleted: true`. Routes: `resources "/documents", only: [:index,:create,:show,:update,:delete]` + `post "/documents/:id/restore"`. Schema `Document` (`title`,`content`,`deleted_at :utc_datetime`) with two changesets: `changeset/2` (casts only title/content, `validate_required` + `validate_length(:title, min: 1)`) and `soft_delete_changeset/2` (casts only `:deleted_at`).
- **Approach**: `maybe_exclude_deleted(query, false)` adds `where is_nil(d.deleted_at)`. Soft-delete/restore implemented as **guard-clause no-ops**: `soft_delete_document(%{deleted_at: dt}) when not is_nil(dt)` returns `{:ok, doc}` unchanged; `restore_document(%{deleted_at: nil})` same. `deleted_at` set to `DateTime.utc_now() |> DateTime.truncate(:second)`. Update deliberately can't touch `deleted_at` (not in cast list). Full Phoenix app scaffold present (mix.exs, config/*, endpoint, `FallbackController`, `ErrorJSON` with `traverse_errors`).
- **Key invariants tested**: 422 on missing/blank title or missing content; default listings hide soft-deleted; `?include_deleted=true` shows them; write endpoints (PUT/DELETE) 404 on already-deleted; DELETE returns 200+doc, double-delete→404; restore no-op→200; `deleted_at` valid ISO8601; full lifecycle create→update→delete→restore; update can't set `deleted_at`.
- **Notable**: only task shipping a full mix project skeleton; uses Bandit adapter, `action_fallback`.

### 019 bulk_create_endpoint_with_partial_failure_reporting — Bulk Create w/ Partial Failures (UNSOLVED)
- **Interface**: `MyApp.Catalog.bulk_create_items(list_of_attrs, opts \\ [])` — default all-or-nothing → `{:ok|:error, results}` where results are `{index, :ok, item} | {index, :error, changeset}`; `partial: true` inserts valid rows individually. Controller `MyAppWeb.BulkItemController.create/2`, route `post "/api/items/bulk"`. Schema `MyApp.Catalog.Item`: `name` (1–255), `price` (int > 0), `description` (optional, ≤1000).
- **Approach (required)**: default mode wraps in one `Repo.transaction`, any changeset invalid → roll back (zero rows). Partial mode persists valids, skips invalids. Every result entry carries **zero-based original index**. Controller reads `?partial=true` (literal `"true"` only), rejects missing/non-list `"items"` with 400 `{"error":"expected a list of items"}`. Responses: all-created→201 `{status:"all_created", items:[{index,id,name,price,description}]}`; all-failed→422 `{status:"all_failed", errors:[{index,errors}|{index,valid:true}]}`; partial→201 `{status:"partial", created:[…], errors:[…]}`.
- **Key invariants tested**: index correctness for multiple/interleaved failures (incl. only-last-item-fails full rollback via `Repo.aggregate(Item,:count)==0`); partial indices e.g. created `[0,2,4]` / errors `[1,3]`; empty list→201 empty; 50-item batch; created rows fetchable & IDs match DB; description exactly 1000 ok / 1001 fails.
- **Notable**: distinguishes strict transactional rollback vs per-item partial persistence; assumes existing `MyApp.Repo`.

### 020 file_upload_with_validation — Plug File Upload (UNSOLVED, no Phoenix)
- **Interface**: `FileUpload.Router` (`Plug.Router`) `POST /api/uploads`, init opts `:store`/`:upload_dir`/`:base_url`. `FileUpload.Validator.validate(%Plug.Upload{})` → `:ok | {:error, reason}`. `FileUpload.Store` GenServer: `start_link(name:)`, `save/2` (generates UUIDv4 id + ISO8601 `uploaded_at`, returns `{:ok, meta}`), `get/2`→`{:ok,meta}|{:error,:not_found}`, `list/1`.
- **Approach (required)**: `Plug.Parsers` multipart with `:length` 5_242_880; over-limit→413 `{"error":"File too large","max_bytes":5242880}`. Field `"file"`; missing→422 `{"error":"No file provided"}`. Validator: allow only `.csv`/`.json` (case-insensitive on `filename`); CSV must have header-ish content (≥2 lines or comma-separated line) else `Invalid CSV: …`; JSON via `Jason.decode` else `Invalid JSON: <desc>`. Success 201 with `{id, original_name, size, content_type, uploaded_at, download_url}`; file saved to disk as `<uuid><ext>` to avoid collisions.
- **Key invariants tested**: id length 36; size==byte_size; file persisted at `upload_dir/<id>.csv` with exact bytes; rejects `.txt/.exe/no-ext`; case-insensitive `.CSV/.JSON`; 413 just over 5MB, 201 just under; empty/single-value CSV→422; malformed/empty JSON→422 but JSON arrays & primitives accepted; store `get`/`list`; download_url starts with base_url and contains id; same filename twice→distinct ids.
- **Notable**: uses `Plug.Test`; UUID must be self-generated (no external uuid lib).

### 021 versioned_api_with_content_negotiation — Header-Based API Versioning (UNSOLVED, Plug)
- **Interface**: `VersionedApi.Router` (`Plug.Router`) `GET /api/users/:id`; `VersionedApi.Plugs.ApiVersion` plug (opts `:supported` list, `:default`); `VersionedApi.Views.UserView.render(version, user)`. In-memory user map (module attribute), ids `"1"` Alice/Smith, `"2"` Bob/Jones.
- **Approach (required)**: plug reads `accept-version` header → resolves to `conn.assigns[:api_version]`; absent→default `"v2"`; unsupported→halt 406 `{"error":"unsupported version","supported":["v1","v2"]}`. `v1` shape `%{name: "First Last", email}`; `v2` shape `%{first_name, last_name, email, created_at}`. Unknown id→404 `{"error":"not found"}`. All responses `content-type: application/json` via Jason.
- **Key invariants tested**: exclusive key sets per version (v1 lacks first/last/created_at; v2 lacks name); default == explicit v2; 406 for `v3`/`v99`/`banana` incl. before user lookup (plug halts pre-match); 404 for missing user across all versions; content-type on 200/404/406; unmatched route→404.
- **Notable**: test helper has an intentional flipped-`reduce` red herring then a corrected version; `@opts = Router.init([])` at module load.

### 022 nested_resource_endpoint_with_authorization — Nested Resource + Bearer Authz (UNSOLVED, Plug)
- **Interface**: `TeamStore` GenServer: `start_link(name:)`, `create_user/3(id,token)`, `create_team/2`, `add_member/3` (seed), `get_user_by_token/2`→`{:ok,uid}|:error`, `team_exists?/2`, `is_member?/3`, `list_members/2`→`{:ok,[uid]}|{:error,:not_found}`, `add_member_safe/3`→`{:ok,uid}|{:error,:not_found}|{:error,:conflict}`. `AuthPlug` (opt `:store`) reads `Bearer <token>`, assigns `:current_user`, else halt 401 `{"error":"unauthorized"}`. `TeamRouter` (`Plug.Router`, opt `:store`) `GET`/`POST /api/teams/:team_id/members`.
- **Approach (required)**: plug AuthPlug before match. GET: team missing→404 `not_found`; non-member→403 `forbidden`; else 200 `{"members":[…]}`. POST body `{"user_id":…}`: same 404/403; already member→409 `conflict`; success 201 `{"added":user_id}`. All JSON.
- **Key invariants tested**: **ordering precedence** 401(auth) → 404(team) → 403(membership) → 409(conflict); team isolation (team-1 ops don't touch team-2); malformed/missing `user_id`→400 or 422; content-type json; direct `TeamStore` API return values.
- **Notable**: tests also stash store via `put_private(:team_store, store)` and pass `store:` to `init/1`; unique per-test store name.

### 023 idempotent_post_endpoint — Idempotent Payments GenServer (UNSOLVED, pure OTP)
- **Interface**: `IdempotentPayments.start_link(opts)` opts `:clock` (0-arity ms fn, default `System.monotonic_time(:millisecond)`), `:ttl_ms` (default 86_400_000), `:cleanup_interval_ms` (default 60_000, `:infinity` disables). `process_payment(server, params, idempotency_key \\ nil)`; `get_payments/1`; `get_payment/2`→`{:ok,p}|{:error,:not_found}`. `params` map keys `:amount`,`:currency`,`:recipient`.
- **Approach (required)**: nil key→always new record. Seen unexpired key→return **identical cached response**, no new record. Expired/unseen key→process, cache `{response, expiry}` with TTL. Missing fields→`{:error,:invalid_params}`, and cache the error under the key too. Response `%{id, amount, currency, recipient, status:"completed", created_at: clock()}`; ids sequential `"pay_1"…`. Periodic `:cleanup` via `Process.send_after` + `handle_info` purges only expired idempotency entries; payment records never purged. State exposes `state.idempotency_keys` as `%{key => {resp, expiry}}`.
- **Key invariants tested**: replay identical even when params differ; TTL boundary — valid at +9_999, reprocess at +10_001 (setup `ttl_ms: 10_000`); distinct keys distinct records; error caching creates 0 records; cleanup keeps 50 payment records but drops keys (asserts via `:sys.get_state`); interleaved idem/non-idem counts; sequential unique ids.
- **Notable**: test injects `Clock` Agent as `:clock`; drives cleanup by `send(pid, :cleanup)` then `:sys.get_state` to sync.

### 024 webhook_receiver_with_signature_verification — HMAC Webhook Receiver (UNSOLVED, Plug)
- **Interface**: `WebhookReceiver.Router` (`Plug.Router`) `POST /api/webhooks/stripe`, init opts `:secret`, `:store`. `WebhookReceiver.Signature.verify(payload, signature, secret)`→`:ok|:error`. `WebhookReceiver.Store` behaviour callbacks `store_event/3`→`{:ok,:duplicate|:created}`, `get_event/2`→`{:ok,event}|:error`, `all_events/1`. `WebhookReceiver.MemoryStore` GenServer impl.
- **Approach (required)**: signature = `:crypto.mac(:hmac,:sha256,secret,payload)` hex-encoded, **constant-time** compare. Router: read raw body (custom body reader or cache in assigns — needed for both verify AND decode), header `stripe-signature`; missing/empty/mismatch→401 `{"error":"invalid_signature"}`; then `Jason.decode`, extract `"id"`; malformed JSON or missing id→400 `{"error":"bad_payload"}`; new→store status `:pending`, 200 `{"status":"received"}`; duplicate id→200 `{"status":"duplicate"}`. Event map `%{event_id, payload(decoded map), status: :pending}`.
- **Key invariants tested**: tampered payload→401; duplicate by id even with different body (original payload preserved, not overwritten); 5 distinct ids stored independently; `Signature.verify` direct (`:ok`, wrong→`:error`, non-hex garbage→`:error`); GET to webhook path→404/405; unknown path→404. Test signs with `Base.encode16(case: :lower)`.
- **Notable**: raw-body preservation is the crux (Plug consumes body); tests build a throwaway `defmodule :"TestRouter_#{unique}"` then actually call `Router.init/1`+`call/2` directly.

### 025 long_polling_endpoint — Long-Polling Notifications (UNSOLVED, OTP + Plug)
- **Interface**: `Notifications.start_link(name: Notifications)`; `subscribe(server \\ Notifications, user_id)` (delivers `{:notification, payload}` to caller); `publish(server \\ Notifications, user_id, payload)`→`:ok`. `NotificationPoller` plug `GET /api/notifications/poll` opts `:notifications_server`, `:timeout_ms` (default 30_000). `NotificationRouter` (`Plug.Router`, `:match`/`:dispatch`) forwards poll route, 404 else, passes opts through.
- **Approach (required)**: pub/sub via `Registry` in `:duplicate` mode (no Phoenix.PubSub). Poller reads `conn.assigns.user_id`; missing→401 body `"unauthorized"`; subscribes then **blocking `receive … after timeout_ms`**; notification within timeout→200 `application/json` JSON-encoded payload; timeout→204 empty body. Must truly block (no sleep-poll loop).
- **Key invariants tested**: publish during in-flight poll returns 200 payload; no publish→204 empty; missing user_id→401; per-user isolation (A's publish doesn't wake B, B times out 204); correct routing among multiple pollers; multiple pollers same user all get it (duplicate registry); only first notification returned (single-shot, `seq:1` not `seq:2`); unicode/nested payloads; publish to no subscribers doesn't crash; unknown path→404; direct subscribe/publish delivers `{:notification, map}`.
- **Notable**: tests use `Task.async` + `Process.sleep(100)` to interleave subscribe/publish, short `timeout_ms: 500`.

### 102 genserver_based_state_machine_with_persistence — Persisted State Machine (SOLVED)
- **Interface**: `StateMachine.start_link(opts)` (opts `:repo` required, `:name` optional); `start(server, entity_id)`→`{:ok, state}` (hydrate from DB or `:pending`); `get_state/2`→`{:ok,state}|{:error,:not_found}` (in-memory only); `transition(server, entity_id, event)`→`{:ok,new}|{:error,:invalid_transition|:not_found|{:db_error,reason}}`; `history/2`→`{:ok,[%{event,from_state,to_state,inserted_at}]}` chronological. Plus `EntityTransition` Ecto schema (`entity_transitions` table) + migration.
- **Approach**: transition table is compile-time `@transitions` map keyed `{state, event}` (pending+confirm→confirmed, confirmed+ship→shipped, shipped+deliver→delivered, pending/confirmed+cancel→cancelled); `@initial_state :pending`. State = `%{repo:, entities: %{id => state_atom}}`. **All ops are `handle_call`** so concurrent callers serialize (no races); `transition` uses `with` pipeline `entity_lookup → resolve_transition → persist` and only updates in-memory map **after** DB insert succeeds. `persist/5` wraps `repo.insert(changeset)` in try/rescue → `{:db_error, reason}` on failure, never mutating state. `load_latest_state` = `order_by desc inserted_at, limit 1`; string columns re-atomized via `String.to_existing_atom` (safety: `@states` kept alive by `__states__/0`). Schema uses `@timestamps_opts [type: :utc_datetime_usec, updated_at: false]`.
- **Key invariants tested**: new entity→`:pending`; full happy path; both cancel paths; invalid/terminal transitions leave state unchanged & write nothing; transition on unknown entity→`:not_found`; history ordered & per-entity scoped; **restart recovery** (kill GenServer, new one re-hydrates `:shipped` from DB then accepts `:deliver`); **concurrency** — 20 concurrent `:confirm` on same entity yield exactly 1 `{:ok,:confirmed}` + 19 `:invalid_transition`; concurrent transitions on different entities all succeed.
- **Notable**: test ships a `FakeRepo` Agent-backed in-memory shim mimicking `insert/1`,`all/2`,`one/2` incl. crude `Ecto.Query` where-param extraction — solution deliberately avoids `select:` so real repo and FakeRepo both return full structs; `async: false`.

---

## Notable findings, caveats & gotchas

Things that are non-obvious or that surfaced during the per-family deep read above:

- **Dead `ElixirBenchmark.Repo` reference.** `test/test_helper.exs` conditionally starts
  `ElixirBenchmark.Repo`, but no such module exists in `lib/`. It's harmless because `:database`
  is excluded by default and no harness is tagged `:database`. The DB-touching tasks (032 Ecto
  ingestion, 102 state machine) instead spin **in-memory SQLite** or a **fake repo Agent** inside
  their own harness — they don't rely on the project-level repo.
- **Only one alternate-model solution exists** and it is a *negative* example: the Qwen3.5-4B trie
  (`tasks/076_001_trie_01/solution_Qwen3.5-4B-Q6_K_gguf.ex`) does not compile/pass and lacks
  moduledoc/spec/doc — it exists to illustrate the house style by contrast and to exercise the
  `run_all.exs <solution_filename>` multi-solution mechanism.
- **Latent bugs the harnesses don't catch.** A few solutions pass only because tests assert a weaker
  property than the prompt implies:
  - `001_004_penalty_escalation` cleanup uses `Enum.take_while(ts > now)`, effectively dropping all
    real (past) timestamps in the sweep (because `window_ms` isn't available in `:cleanup`); the
    harness only checks a "fresh key behaves cleanly" property. The solution also carries emoji
    self-fix comments (`# ✅ FIX…`), evidence of iterative debugging.
  - `007_004_cusumanomaly` diverges from its prompt: after an alert it *freezes* the stream
    (`alerted: true`, returns `:warming_up`) until an explicit `reset`, rather than
    reset-and-re-learn immediately; it also has an undocumented near-zero-variance guard.
  - `012_002_subscription` adds an unspecified `:not_active` rule for cancel-from-pending.
- **Boundary conventions vary intentionally per task** and are load-bearing in tests: sliding-window
  limiters assert `retry_after` in a *range*, fixed-window assert it *exactly*; `098` token expiry is
  strict `<` (equal = expired); `626` TSDB uses inclusive `query` bounds but half-open aggregation
  windows. Read each harness for the exact inequality.
- **Determinism is achieved two ways.** Time-based families inject a fake `Clock` Agent and drive
  `:cleanup` manually (fully deterministic). A handful of concurrency families (009, 061–064) instead
  use real `Process.sleep`/`:timer.tc` + `Agent` counters and assert timing bands — these are the
  least deterministic harnesses.
- **The `_02+` FIM dirs have no harness**, so they are *not* scored by `run_all.exs` (which globs on
  `test_harness.exs`). They are pure training material; correctness is implicitly guaranteed because
  each FIM `solution.ex` is lifted verbatim from an already-passing `_01` module.
- **Seven `tasks_multifile/` tasks are unsolved** (019–025: `prompt.md` + `test_harness.exs`, no
  `solution.ex`) — a ready-made backlog of harnessed-but-unimplemented tasks.
- **The idea catalog is ~94% unrealized.** `tasks.md` + `tasks_external.md` enumerate ~1000 base ideas
  (plus ~51 written variations); only ~57 base ideas (IDs mostly ≤101, plus 623–626) have been built.
  Treat the two `.md` files as a roadmap/backlog, not an index of what exists.

## How to run / quick reference

```bash
# One-time setup
mix deps.get
mix compile

# Evaluate a single task's reference solution (task 8, variation 1) as scored JSON
mix run ./scripts/eval_task.exs 8 | jq
mix run ./scripts/eval_task.exs 8 2 | jq          # variation 2
mix run ./scripts/eval_task.exs 76 1 solution_Qwen3.5-4B-Q6_K_gguf.ex | jq   # alternate solution

# Batch-evaluate every task's solution.ex (or any alternate filename)
elixir scripts/run_all.exs solution.ex --parallel 4
#   → results/<task>.json, results/report_<ts>.json, results/summary_<ts>.txt

# Sanity-check that every harness at least compiles
./scripts/validate_harnesses.sh

# Quality gate: every reference green + every FIM target actually exercised (mutation)
elixir ./scripts/validate.exs

# Dataset summary for SFT planning (example counts by shape, token volume, distributions,
# context-window fit, diversity, quality signals, roadmap coverage; add --json)
mix run scripts/dataset_stats.exs

# Format everything (incl. task .exs files)
mix format

# Automated generation loop (docs/04) — needs the `claude` CLI logged in, ANTHROPIC_API_KEY unset
mix run scripts/generate.exs 80          # one idea, end-to-end (base → variations → FIM)
GEN_DRY_RUN=1 mix run scripts/generate.exs 80   # generate + grade, write nothing
GEN_LIMIT=5 mix run scripts/generate.exs        # first 5 pending ideas
nohup mix run scripts/generate.exs > logs/loop_console.log 2>&1 &   # whole catalog, detached
```

Adding a task follows the README's contribution workflow (§6 above): expand an idea from `tasks.md`
with `single_shot_prompt.md`, drop `prompt.md` + `test_harness.exs` into a new `{a}_001_{name}_01/`
dir, generate a solution, iterate against `eval_task.exs` until green, then optionally add variations
(`variation_prompt.md`) and FIM subtasks (`fill_in_the_middle_prompt.md`). To do all of that
automatically, run `scripts/generate.exs` (README "Automated generation loop"; design in `docs/04`).
