# Task Dependency Resolver and Executor

Write me an Elixir `GenServer` module called `TaskRunner` that accepts tasks with
dependencies and executes them in a valid order, running independent tasks
concurrently.

## Public API

- `TaskRunner.start_link(opts)` — starts the process. It must accept a `:name`
  option used for process registration (so the process can be referred to by an
  atom name in the other functions). Return the usual `{:ok, pid}`.

- `TaskRunner.submit(name, task_id, opts)` — registers a task with the runner.
  - `name` is the registered process name.
  - `task_id` is any term that uniquely identifies the task (typically an atom).
  - `opts` is a keyword list with:
    - `:depends_on` — a list of `task_id`s this task depends on. Optional,
      defaults to `[]`.
    - `:func` — a zero-arity function (`fn -> ... end`) to execute. Required.
  - Returns `:ok`. Submitting the same `task_id` again should overwrite the
    previous definition. Tasks are only *registered* by `submit/3`; none of the
    functions run until `run_all/1` is called.

- `TaskRunner.run_all(name)` — validates the dependency graph, then executes all
  submitted tasks.
  - It must perform a topological sort so that a task's `:func` only begins
    executing **after every one of its dependencies has finished executing**.
  - Tasks whose dependencies are all satisfied and that do not depend on one
    another must run **in parallel** (concurrently), not sequentially.
  - On success it returns `{:ok, results}` where `results` is a map from
    `task_id` to the value returned by that task's `:func`.
  - If the dependency graph contains a cycle, it must **not** execute any task
    and must return `{:error, {:cycle, involved}}`, where `involved` is a list of
    the `task_id`s participating in a cycle.
  - If any task lists a dependency that was never submitted, it must **not**
    execute any task and must return
    `{:error, {:unknown_dependencies, missing}}`, where `missing` is a list of
    the referenced-but-unknown `task_id`s.
  - Calling `run_all/1` on a runner with no submitted tasks returns `{:ok, %{}}`.

## Notes

- Use only the OTP standard library — no external dependencies.
- Give me the complete module in a single file.
- The design goal is correctness of ordering *and* real parallelism: a wide layer
  of independent tasks should take roughly as long as the single slowest task in
  that layer, not the sum of them.