# Elixir Benchmark Suite

A framework for evaluating AI-generated Elixir code against verified test harnesses.
Each solution runs in its own BEAM process — a non-compiling solution cannot affect
any other task's evaluation.

The evaluator (`lib/eval_task/`, driven by `scripts/eval_task.exs`) auto-detects and grades
**five task shapes**:

- **single-file** — one module + `test_harness.exs` (`tasks/<name>/`)
- **multi-file** — a `tasks/<name>/` whose `solution.ex` is a `<file path="…">…</file>` bundle
  (controller + schema + migration + …); self-contained bundles (Plug/GenServer) run as-is, while
  Phoenix + Ecto bundles are graded against a generated in-BEAM SQLite host kit
- **fill-in-the-middle (FIM)** — a `_02+` subtask dir with only a `prompt.md` (module with a
  `# TODO`) + a single-function `solution.ex`; the evaluator reconstructs the full module from
  the prompt skeleton and runs the parent `_01` harness against it
- **write-tests (`wt_` prefix)** — prompt = module + spec, completion = the harness
- **test-FIM (`tfim_` prefix)** — prompt = module + harness with one `test` blanked,
  completion = that gold test block; reconstructed and run against the parent module

plus **`repair_` dirs** — verified bug→fix pairs minted deterministically from captured
generation attempts (broken code + failure report → the accepted fix); they grade as
single-file tasks.

Scoring is `tests·0.7 + analysis·0.2 + compilation·0.1`, with hard-fails: `overall`
is 0.0 when nothing compiles, when zero tests ran, or when any test errored. The
analysis component (moduledoc, `@spec`, `@doc`, line-length ≤98, no-TODO, no-SQLi;
8 points) is real — a solution missing docs scores below 1.0.

## Prerequisites

- Elixir 1.20.2 / OTP 29 — pinned in `.tool-versions`; this is the toolchain the
  corpus is validated under (1.17+/OTP 27+ still compiles, but formatter output and
  warning sets differ across versions, so gate results are only reproducible on the pin)
- PostgreSQL 16+ (only for tasks marked `db: :postgres` — currently
  `017_001_search_endpoint_with_filtering_and_sorting`, which uses `ILIKE`). SQLite-in-BEAM is
  the default and needs no external service. The easiest way to provide Postgres is the bundled
  `docker compose up -d db`. **If it is not running, those tasks grade RED (not skipped)** with a
  message telling you to start it — so you never silently miss coverage.

## Setup

```bash
mix deps.get
mix compile   # required — the evaluator lives in lib/ and is compiled

# Only needed to grade `db: :postgres` tasks (else they go red):
docker compose up -d db      # throwaway Postgres on localhost:5432; `docker compose down` to stop
```

## Evaluating solutions

```bash
# a single task — by number, or by directory (any shape auto-detected)
mix run ./scripts/eval_task.exs 8 | jq                 # single-file, task 8 variation 1
mix run ./scripts/eval_task.exs 16 1 | jq              # multi-file, addressed by number
mix run ./scripts/eval_task.exs tasks/001_001_rate_limiter_02 | jq   # a FIM subtask
# alternate model output: pass a solution filename in the dir
mix run ./scripts/eval_task.exs tasks/076_001_trie_01 solution_Qwen3.5-4B-Q6_K_gguf.ex | jq

# the whole corpus (single-file + multi-file + FIM), one BEAM per task
elixir ./scripts/run_all.exs --parallel 6
#   → results/<task>.json, results/report_<ts>.json, results/summary_<ts>.txt

# quality gate — DEFAULT: perfect-score. Every task must satisfy the RAW invariants
# (0 failed, 0 errors, ≥1 passed, 0 warnings, full analysis), not the rounded overall.
# Missing/unclassifiable task dirs are reported as failures, never skipped. Every eval
# runs under a wall-clock KILL (EVAL_TIMEOUT_S, default 240s). Flakes recovered by the
# serial re-check still pass but are appended to logs/flaky.jsonl — a repeat offender
# there needs a fake clock, not forgiveness.
elixir ./scripts/validate.exs                    # perfect-score, whole corpus
elixir ./scripts/validate.exs --green            # lighter: compiles + tests pass only
elixir ./scripts/validate.exs --fim              # FIM raise-mutant must fail the parent harness
elixir ./scripts/validate.exs --mutants          # single/multifile/wt_: whole-solution raise-
                                                 #   mutant must make the harness FAIL — the
                                                 #   deterministic vacuous-harness detector
elixir ./scripts/validate.exs --stability 3      # flake recovery needs 3 consecutive serial passes
elixir ./scripts/validate.exs --only "001_001*"  # restrict any mode to matching task names

# canonical-format gate (docs/10 R6): the whole corpus is Code.format_string! output
# under the .tool-versions pin — harnesses, solutions, bundle parts, fim/tfim fragments,
# and the ```elixir fences embedded in fim/tfim/wt_ prompts (_01 prompts excluded: the
# blind-screen ledger is keyed by prompt sha). Generation keeps itself canonical via
# Evaluator.autoformat/1; this script guards the corpus (runs in CI + pre-push).
elixir ./scripts/format_corpus.exs --check       # exit 1 on any deviation
elixir ./scripts/format_corpus.exs --apply       # rewrite deviating files

# blind-solve SCREEN (costs LLM calls — one `claude -p` per unscreened _01): a task is
# well-specified iff an independent solver goes green from prompt.md ALONE. Failures
# quarantine to logs/screen_blind.jsonl (prompt under-specified OR solver too weak —
# human decides). Content-keyed ledger: interrupted runs resume; fixed prompts re-screen.
mix run scripts/screen_blind_solve.exs --limit 10        # first 10 unscreened
mix run scripts/screen_blind_solve.exs --only "001_*"    # name filter
mix run scripts/screen_blind_solve.exs --report          # no calls; summarize ledger
mix run scripts/screen_blind_solve.exs                   # full corpus (~299 calls, hours)

# unit tests for the evaluator itself
mix test test/eval_task

# local pre-push gate (mix test + perfect/mutant/format gates on touched families):
git config core.hooksPath .githooks
# CI (.github/workflows/validate.yml) runs test + format + mutant gates per push,
# and the full perfect + FIM sweep weekly / on manual dispatch.

# dataset summary for SFT planning — example counts by shape, token volume, length
# distributions, context-window fit, diversity, quality signals, roadmap coverage
mix run scripts/dataset_stats.exs                      # pretty report
mix run scripts/dataset_stats.exs --json               # machine-readable
mix run scripts/dataset_stats.exs --chars-per-token 3.5   # tune the token estimate

# assertion-tightness measurement (docs/10 R10, report-only): semantic mutants
# (comparison swap, ±1 on int literals, :ok<->:error, bool flip) of each reference;
# per-task kill rate + corpus histogram + weakest-20; ledger logs/semantic_mutants.jsonl
elixir ./scripts/validate.exs --semantic-mutants --only "003_002*"   # spot check
elixir ./scripts/validate.exs --semantic-mutants                     # full corpus (slow)

# what work still needs to happen on which task sets (re-runnable; rows come from
# the GenTask.Work registry — docs/09 §12). generate.exs performs exactly the
# missing units, so status → generate → status converges.
mix run scripts/work_status.exs             # work-type × corpus matrix
mix run scripts/work_status.exs --pending   # per-seed detail
mix run scripts/work_status.exs --counts    # one compact progress line
```

## Nightly flake sweep (runs on a dedicated machine, not a dev box)

Flaky harnesses are found statistically: a test failure under parallel load that
recovers serially is appended to `logs/flaky.jsonl` **with the failing test name and
assertion message**; a task (stronger: the same test) reaching **≥2 ledger occurrences**
is the threshold for fixing it (docs/10 R9 — widen wall-clock bounds or inject a fake
clock, never weaken assertions). The evidence only accumulates when full sweeps run
regularly, so schedule `scripts/nightly_sweep.sh` from cron on whichever machine owns
this job. No LLM calls are made — it is pure CPU work (~15 min on 16 cores).

Setup on the sweep machine:

```bash
git clone <this-repo> && cd elixir-sft-dataset
# toolchain: install the EXACT .tool-versions pin (asdf install / mise install) —
# gate results are only reproducible on the pin
mix deps.get && mix compile
docker compose up -d db        # optional; without it the db-tagged task grades RED
crontab -e                     # then add:
# 17 3 * * * cd /path/to/elixir-sft-dataset && ./scripts/nightly_sweep.sh
```

The script compiles first (stale beams silently run old logic), runs
`validate.exs --stability 3`, prints the ledger's per-task and per-test aggregation,
and keeps the last 30 logs under `logs/nightly/`. It exits non-zero on any hard
failure — wire cron mail or your monitoring to that. `logs/` is gitignored: sync
`logs/flaky.jsonl` back to wherever triage happens (commit it from the sweep machine,
or fetch it) — the ledger, not the sweep console, is the artifact that matters.

## Naming convention

```
001_001_rate_limiter_01
 a   b        c       d


a - task number
b - task variation number (01 - original task, 02..0x - variations generated later)
c - task name
d - subtask number(01 - single-hot, 02..0x - fill-in-the-middle functions)
```

Two **derived task kinds** are minted from every solved `_01` (deterministically, no LLM — see
`docs/06-dataset-multiplication.md`), distinguished by a directory **prefix**:

```
wt_001_001_rate_limiter          # "write tests for this module": prompt = module (+spec) → completion = a harness
tfim_001_001_rate_limiter_02     # test fill-in-the-middle: prompt = harness with one `test` blanked → that test
```

`wt_` dirs carry `solution.ex` (the module under test) + `test_harness.exs` (the gold harness).
`tfim_` dirs carry `solution.ex` (the one gold `test` block) and reconstruct against the parent `_01`.
The evaluator (`eval_task.exs`) auto-detects these shapes (`:write_test` / `:test_fim`) by prefix.

A third derived kind, **`repair_<id>_<NN>`**, is minted by `scripts/mint_repairs.exs` from
captured generation attempts: `prompt.md` = the original request + the broken attempt + its
real failure report; `solution.ex`/`test_harness.exs` = the accepted fix. Every pair is
double-verified before minting (fix green AND broken red against the same harness).

## Design & internals

The multi-file and FIM auto-testing design, decisions, and the as-built evaluator (module layout,
scoring, the Phoenix/SQLite host kit, the validator, known issues) are documented in `docs/`:

- `docs/01-multifile-task-support.md` — multi-file design + prototypes
- `docs/02-multifile-task-breakdown.md` — decisions + task backlog
- `docs/03-implementation-spec.md` — the definitive how-it-works + per-task status + known issues
- `docs/04-task-generation-loop.md` — the automated generation loop (design + env knobs)
- `docs/05-generation-loop-audit.md` — loop audit + fixes
- `docs/06-dataset-multiplication.md` — the derived `wt_`/`tfim_` minting design
- `docs/07-dataset-audit-and-growth-roadmap.md` — dataset-level audit + growth roadmap
- `docs/08-gate-fixes-and-attempt-capture.md` — gate fixes; per-attempt capture (repair-pair source)
- `docs/09-loop-hardening.md` — work registry, backfill, loop hardening
- `docs/10-quality-assurance-audit.md` — **the QA audit campaign (2026-07)**: blind-solve
  screen (250/299 green, every red a judge-confirmed hard-task keep), prompt↔harness
  consistency backfills, mutation/format/flake gates, CI — read its §7 orientation first

## How to contribute:

There are multiple activities that people can do:
- implement single file task out of `tasks/tasks.md` file
- implement a multi-file task under `tasks/` (bundle the modules as `<file path="…">…</file>`
  blocks in `solution.ex`; Phoenix bundles should be *domain-only* — the host kit supplies
  Repo/Endpoint/ConnCase). Multi-file, single-file, and FIM tasks all share the `a_b_c_d` naming
  and the same `tasks/` directory; the evaluator auto-detects the shape from the solution content.
- generate variations of the tasks
- generate subtasks (fill-in-the-middle)

After adding or changing a task, run the gates scoped to it (the pre-push hook does this
automatically for touched families):

```bash
elixir ./scripts/validate.exs --only "<family>*"            # perfect-score
elixir ./scripts/validate.exs --mutants --only "<family>*"  # harness kills a raise-mutant
elixir ./scripts/format_corpus.exs --check --only "<family>*"  # canonical formatting
```

Editing any `_01` task **cascades**: its FIM children, `wt_` copy, and `tfim_` children embed
the parent's module/harness text verbatim — `ls tasks/ | grep <NNN>_<VVV>` before editing and
re-validate the whole family (`--only "*<NNN>_<VVV>*"`). Prompt edits to `_01` tasks change
their sha in the blind-screen ledger and will re-screen (one LLM call) on the next screen run.

> **Note (2026-07):** the step-by-step manual workflows below predate the automated
> generation loop and are kept for historical reference — the loop (next section) performs
> all three end-to-end with grading, repair, and mutation/quality gates. The meta-prompts
> they reference (`tasks/single_shot_prompt.md`, `variation_prompt.md`,
> `fill_in_the_middle_prompt.md`) are NOT what the loop uses (its templates live in
> `lib/gen_task/prompts.ex`).

### Implement single file task out of `tasks/tasks.md` file

Anyone is invited to contribute solutions / harnesses. Please don't do too many at once as there could be a clash of doubled effort(same tasks solved).

Step 1. Grab a prompt from `tasks/single_shot_prompt.md`
Step 2. Substitute this block:

```
### 80. Directed Acyclic Graph with Topological Sort
Build a DAG module. The interface is `DAG.new()`, `DAG.add_vertex(dag, vertex)`, `DAG.add_edge(dag, from, to)` (fails if it would create a cycle), `DAG.topological_sort(dag)` returning a valid ordering, and `DAG.predecessors(dag, vertex)` / `DAG.successors(dag, vertex)`. Verify by building a known dependency graph, asserting the topological sort is valid (every vertex appears before its dependents), that adding a cycle-creating edge returns an error, and that predecessor/successor queries return correct results.
```

with any of the ideas from `tasks/tasks.md` list that aren't done yet.

Step 3. Leave the rest as is and attach the test harness of the task 1 (as an example) `tasks/001_rate_limiter/test_harness.exs`

Step 4. Create new directory that is based on the title of the task (including the number it will be like `${task_number}_001_${lowercased_name_of_the_task_with_underscores_only}_01`) and put `prompt.md` and `test_harness.exs` there

Step 5. Start a new LLM session and paste there just the contents of the `prompt.md`

Step 6. Store results in the `solution.ex`

Step 7. Confirm that the tests are actually passing:

```
mix run ./scripts/eval_task.exs <YOUR_TASK_NUMBER_HERE> 1 | jq
```

Step 8. Fix any problems (most of the time by submitting the report out of the `eval_task.exs` command and `test_harness.exs` file and say can it fix it)

Step 9. Create a PR

Step 10. Look through `solution.ex` and find good candidates functions for secondary tests (the "fill-in-the-middle" type)

Step 11. Include `solution.ex` and ask can LLM generate a task to write specific function

### Generate variations of the tasks

Step 1. Pick up a task that has only a single variation (only `xyz_001_..._01` but not `xyz_002_..._01` etc)

Step 2. Put contents of the `tasks/variation_prompt.md` file into an LLM TOGETHER with 3 files out of the first variation of the task (for example `tasks/002_003_progressive_recovery_cb_01/prompt.md`, `tasks/002_003_progressive_recovery_cb_01/solution.ex` and `tasks/002_003_progressive_recovery_cb_01/test_harness.exs`)

Step 3. Hopefully you will get 10 files - update the `tasks/tasks.md` with the descriptions of the variations, create new directories for those variations where you put file triplets

### Generate subtasks

Step 1. Find task with no subtasks (`abc_def_some_name_01` but not `abc_def_some_name_02`)

Step 2. Ask LLM (attach the `solution.ex` file):

"""
which of these function would be the best candidates for "Fill-in-the middle" SFT training?
"""

Step 3. You will get a list of best candidates and you can use it to fill the `tasks/fill_in_the_middle_prompt.md` prompt.

Step 4. You will get prompts for each of the functions - you need to create folder for each and have `solution.ex` and `prompt.md` there.

Step 5. Under each of the prompts inside the `prompt.md` file add the following:

"""
```elixir
PASTE WHOLE MODULE HERE BUT THE BODY OF THE FUNCTION IN QUESTION NEEDS TO BE REMOVED AND HAVE JUST A SINGLE LINE "# TODO"
```
"""

Step 6. Inside the `solution.ex` put jsut a single function in question

## Automated generation loop (all three workflows, hands-off)

The three manual workflows above are also fully automated by a single non-agentic command that
walks `tasks/tasks.md` and, for each idea, authors the base task, its 3 variations, and FIM
subtasks — grading each with `eval_task.exs`, repairing on failure, and gating on a mutation
check so a vacuous harness can never ship. The full design is in
[`docs/04-task-generation-loop.md`](docs/04-task-generation-loop.md); the code is `lib/gen_task/**`.

**It is safe to run and safe to interrupt.** It only *adds* — new `tasks/…` dirs and
insert-only appends to `tasks.md`; it never edits or deletes an existing task. Progress is
durable: a task already on disk is skipped, so a killed run resumes cleanly by re-running the
same command.

### Prerequisites

- `mix compile` has been run (the loop runs under `mix run`).
- The `claude` CLI is installed and **logged in** (`claude` uses your Claude Max subscription —
  the loop shells out to `claude -p`, so calls are subscription-backed, not pay-per-token).
- `ANTHROPIC_API_KEY` is **unset** in your shell, so the CLI uses the subscription login rather
  than a metered key. Check with `echo $ANTHROPIC_API_KEY` (should be empty); `unset
  ANTHROPIC_API_KEY` if not.

### Running it

```bash
# One base idea, end-to-end (base → variations → FIM) — the recommended smoke test first:
mix run scripts/generate.exs 80

# Dry run — generate + grade + repair but write NOTHING (no promotion, no tasks.md edits):
GEN_DRY_RUN=1 mix run scripts/generate.exs 80

# The first N pending base ideas (plus their derivatives + backfill):
GEN_LIMIT=5 mix run scripts/generate.exs

# The whole catalog — leave it running (overnight is fine; running out of tokens is a
# NORMAL condition: the transport retries every 15 min indefinitely until the 5-hour
# window resets — GEN_USAGE_MAX_WAIT_MS=0 default). ALWAYS launch LLM sweeps through
# the detacher so they survive the launching session being dropped:
scripts/run_detached.sh logs/loop_console.log mix run scripts/generate.exs
```

The two work-lists run in order — **catch-up first, then new ground**:
**backfill** (existing accepted `_01`s missing any registered work — variations, FIM,
wtest, tfim; see `GenTask.Work`), then **new bases** (every idea with no
`tasks/NNN_001_*_01` yet). Both are recomputed from disk each run and every step is
idempotent, so the plain no-flag command repeatedly converges: it brings the existing
record fully up to date, then progresses to new ideas. Catalog reconciliation
(healing missing variation entries) also runs by default (`GEN_RECONCILE=0` to
disable). Terminal output is one line per generated task, `run_all`-style:

```
[  7/494] 065_001_saga_coordinator_01 (base) ... ACCEPTED (17 passed, mutant killed, 2 attempt(s))
```

### Watching / verifying a run

```bash
tail -f logs/loop_console.log                 # the one-line-per-task progress stream
ls logs/errors/                               # any task that failed its accept gate lands here
tail -f logs/runs.jsonl                        # structured ledger: one JSON line per task
git status --short tasks/                       # every new task + tasks.md insert shows in the diff
elixir ./scripts/validate.exs                   # after a run: the perfect-score gate
```

Each generated task also gets a full per-cycle log at `logs/<task_id>.log` (every prompt,
response, eval JSON, and repair attempt). Failed cycles' logs are moved to `logs/errors/`.

Every graded attempt is additionally **captured** to `logs/attempts/<id>/attempt_NN/`
(the exact candidate files + grade JSON + the repair report — docs/08 §4). After a run,
mint verified bug→fix repair tasks from them, deterministically and with no LLM:

```bash
mix run scripts/mint_repairs.exs --dry-run   # see what's mintable
mix run scripts/mint_repairs.exs             # mint tasks/repair_* dirs
```

### Common knobs (env vars — full table in docs/04 §15)

| Env | Default | Effect |
|---|---|---|
| `GEN_DRY_RUN=1` | off | generate + grade but never write to `tasks/` / `tasks.md` |
| `GEN_LIMIT=N` | ∞ | at most N items per work-list (N base ideas AND N backfill seeds) |
| `GEN_TFIM_MAX_PER_TASK=N` | 10 | tfim subtasks carved per `_01` (deterministic, no LLM) |
| `GEN_MAX_TURNS=N` | 2 | `claude -p --max-turns` — 2 absorbs a stray (denied) tool attempt before the real reply |
| `GEN_FROM=a` / `GEN_TO=b` | — | restrict to idea numbers in `[a, b]` |
| `GEN_SKIP_VARIATIONS=1` / `GEN_SKIP_FIM=1` | off | run only part of the per-idea chain |
| `GEN_SKIP_BACKFILL=1` | off | skip the (first-running) backfill work-list; `GEN_ONLY=backfill` runs *only* it |
| `GEN_RETRY_FAILED=1` | off | re-attempt tasks currently sitting in `logs/errors/` |
| `GEN_RECONCILE=0` | on | disable the default catalog healing (insert-only variation entries) |
| `GEN_MAX_RETRIES=N` | 3 | repair iterations per task before it's sent to errors |
| `GEN_SKIP_QUALITY_GATE=1` | off | stop requiring house style (`@moduledoc`/`@spec`/`@doc`, no TODO, zero warnings) on a green base/variation |
| `GEN_SKIP_PER_FN_MUTATION=1` | off | use a single whole-module raise-mutant instead of mutating each public function |
| `GEN_MODEL=…` | `opus` | `claude --model` alias/id |

By default a generated base/variation must be **green, meet the house style (moduledoc/spec/doc,
no TODO, zero compile warnings), and have every public function killed by a raise-mutant** — the
loop repairs shortfalls before accepting. Partially-filled ideas are **topped up** on later runs
(missing variations / FIM subtasks are filled, not skipped).

A single positional integer (`mix run scripts/generate.exs 80`) restricts the run to that one
base idea — the fastest way to try the loop before turning it loose on the catalog.