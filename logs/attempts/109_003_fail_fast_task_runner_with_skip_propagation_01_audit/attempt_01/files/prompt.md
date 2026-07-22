# Fail-Fast Task Runner with Skip Propagation

Write me an Elixir `GenServer` module called `ResilientRunner` that accepts tasks
with dependencies, executes them in a valid order running independent tasks
concurrently, and **handles task failures by skipping their dependents** instead
of crashing. A task's failure must not take down the runner or unrelated
branches — only the tasks that (transitively) depend on the failed task are
skipped.

## Public API

- `ResilientRunner.start_link(opts)` — starts the process. It must accept a
  `:name` option used for process registration. Return the usual `{:ok, pid}`.

- `ResilientRunner.submit(name, task_id, opts)` — registers a task.
  - `opts` is a keyword list with:
    - `:depends_on` — a list of `task_id`s this task depends on. Optional,
      defaults to `[]`.
    - `:func` — a zero-arity function to execute. Required.
  - Returns `:ok`. Submitting the same `task_id` again overwrites the previous
    definition. Nothing runs until `run_all/1` is called.

- `ResilientRunner.run_all(name)` — validates the graph, then executes all tasks.
  - A task's `:func` runs only **after every one of its dependencies has finished
    executing**. Independent tasks that are all ready and do not depend on one
    another run **in parallel**.
  - A task **fails** if its `:func` returns `{:error, reason}` or raises/throws.
    Any other return value is a success, and that value is stored as the result.
  - When a task fails or is skipped, every task that depends on it (directly or
    transitively) is **skipped** — its `:func` is never invoked. Sibling branches
    that do not depend on the failed task must still run to completion.
  - On success (for the graph as a whole, regardless of individual task
    failures) it returns
    `{:ok, %{completed: completed, failed: failed, skipped: skipped}}` where:
    - `completed` is a map from `task_id` to the successful return value,
    - `failed` is a map from `task_id` to the failure reason (a raise/throw is
      captured, never re-raised),
    - `skipped` is a list of the `task_id`s that were never run because an
      upstream task failed or was itself skipped.
  - If the dependency graph contains a cycle, it must **not** execute any task
    and must return `{:error, {:cycle, involved}}`.
  - If any task lists a dependency that was never submitted, it must **not**
    execute any task and must return `{:error, {:unknown_dependencies, missing}}`.
  - Calling `run_all/1` with no submitted tasks returns
    `{:ok, %{completed: %{}, failed: %{}, skipped: []}}`.

## Notes

- Use only the OTP standard library — no external dependencies.
- Give me the complete module in a single file.
- The design goal is correctness of ordering, real parallelism of independent
  ready tasks, and precise failure containment: a failure prunes exactly the
  downstream subgraph and nothing more.