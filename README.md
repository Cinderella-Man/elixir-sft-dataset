# Elixir Benchmark Suite

A framework for evaluating AI-generated Elixir code against verified test harnesses.
Each solution runs in its own BEAM process — a non-compiling solution cannot affect
any other task's evaluation.

The evaluator (`lib/eval_task/`, driven by `scripts/eval_task.exs`) auto-detects and grades
**three task shapes**:

- **single-file** — one module + `test_harness.exs` (`tasks/<name>/`)
- **multi-file** — a `tasks/<name>/` whose `solution.ex` is a `<file path="…">…</file>` bundle
  (controller + schema + migration + …); self-contained bundles (Plug/GenServer) run as-is, while
  Phoenix + Ecto bundles are graded against a generated in-BEAM SQLite host kit
- **fill-in-the-middle (FIM)** — a `_02+` subtask dir with only a `prompt.md` (module with a
  `# TODO`) + a single-function `solution.ex`; the evaluator reconstructs the full module from
  the prompt skeleton and runs the parent `_01` harness against it

Scoring is `tests·0.7 + analysis·0.2 + compilation·0.1`. The analysis component (moduledoc,
`@spec`, `@doc`, line-length ≤98, no-TODO, no-SQLi; 8 points) is real — a solution missing docs
scores below 1.0.

## Prerequisites

- Elixir 1.17+ / OTP 27+
- PostgreSQL 16+ (only for tasks marked `db: :postgres`; SQLite-in-BEAM is the default and needs
  no external service)

## Setup

```bash
mix deps.get
mix compile   # required — the evaluator lives in lib/ and is compiled
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

# quality gate: every reference solution must be green, and every FIM target must be
# exercised (a raise-body mutant must make the parent harness fail)
elixir ./scripts/validate.exs             # reference-green + FIM mutation
elixir ./scripts/validate.exs --fim-only  # just the mutation check

# unit tests for the evaluator itself
mix test test/eval_task
```

## Naming convention

```
001_001_rate_limiter_01
 a   b        c       d


a - task number
b - task variation number (01 - original task, 02..0x - variations generated later)
c - task name
d - subtask number(01 - single-hot, 02..0x - fill-in-the-middle functions)
```

## Design & internals

The multi-file and FIM auto-testing design, decisions, and the as-built evaluator (module layout,
scoring, the Phoenix/SQLite host kit, the validator, known issues) are documented in `docs/`:

- `docs/01-multifile-task-support.md` — multi-file design + prototypes
- `docs/02-multifile-task-breakdown.md` — decisions + task backlog
- `docs/03-implementation-spec.md` — the definitive how-it-works + per-task status + known issues

## How to contribute:

There are multiple activities that people can do:
- implement single file task out of `tasks/tasks.md` file
- implement a multi-file task under `tasks/` (bundle the modules as `<file path="…">…</file>`
  blocks in `solution.ex`; Phoenix bundles should be *domain-only* — the host kit supplies
  Repo/Endpoint/ConnCase). Multi-file, single-file, and FIM tasks all share the `a_b_c_d` naming
  and the same `tasks/` directory; the evaluator auto-detects the shape from the solution content.
- generate variations of the tasks
- generate subtasks (fill-in-the-middle)

After adding or changing a task, run `elixir ./scripts/validate.exs` — it evaluates every
reference solution (catching harness bugs that compile-only checks miss) and confirms each FIM
target is actually exercised by its parent harness.

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