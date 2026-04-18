# Elixir Benchmark Suite

A framework for evaluating AI-generated Elixir code against verified test harnesses.
Each solution runs in its own BEAM process — a non-compiling solution cannot affect
any other task's evaluation.

## Prerequisites

- Elixir 1.17+ / OTP 27+
- PostgreSQL 16+ (only for database-tagged tasks)

## Setup

```bash
mix deps.get
mix compile
```

Test a single task:

```
mix run ./scripts/eval_task.exs 8 | jq
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

## How to contribute:

Anyone is invited to contribute solutions / harnesses. Please don't do too many at once as there could be a clash of doubled effort(same tasks solved).

Step 1. Grab a prompt from `tasks/single_shot_prompt.md`
Step 2. Substitute this block:

```
### 80. Directed Acyclic Graph with Topological Sort
Build a DAG module. The interface is `DAG.new()`, `DAG.add_vertex(dag, vertex)`, `DAG.add_edge(dag, from, to)` (fails if it would create a cycle), `DAG.topological_sort(dag)` returning a valid ordering, and `DAG.predecessors(dag, vertex)` / `DAG.successors(dag, vertex)`. Verify by building a known dependency graph, asserting the topological sort is valid (every vertex appears before its dependents), that adding a cycle-creating edge returns an error, and that predecessor/successor queries return correct results.
```

with any of the ideas from `tasks/tasks.md` list that aren't done yet.

Step 3. Leave the rest as is and attach the test harness of the task 1 (as an example) `tasks/001_rate_limiter/test_harness.exs`

Step 4. Create new directory that is based on the title of the task (including the number) and put `prompt.md` and `test_harness.exs` there

Step 5. Start a new LLM session and paste there just the contents of the `prompt.md`

Step 6. Store results in the `solution.ex`

Step 7. Confirm that the tests are actually passing:

```
mix run ./scripts/eval_task.exs <YOUR_TASK_NUMBER_HERE> | jq
```

Step 8. Fix any problems (most of the time by submitting the report out of the `eval_task.exs` command and `test_harness.exs` file and say can it fix it)

Step 9. Create a PR

Step 10. Look through `solution.ex` and find good candidates functions for secondary tests (the "fill-in-the-middle" type)

Step 11. Include `solution.ex` and ask can LLM generate a task to write specific function