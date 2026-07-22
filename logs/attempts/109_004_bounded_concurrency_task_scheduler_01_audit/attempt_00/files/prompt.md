# Bounded-Concurrency Task Scheduler

Write me an Elixir `GenServer` module called `BoundedRunner` that accepts tasks
with dependencies and executes them in a valid order — but runs **at most
`max_concurrency` tasks at any instant**, even when far more tasks are ready.
Ready tasks beyond the concurrency budget wait for a running slot to free up.

## Public API

- `BoundedRunner.start_link(opts)` — starts the process. It must accept:
  - `:name` — used for process registration.
  - `:max_concurrency` — a positive integer bounding how many tasks may run
    simultaneously. Optional, defaults to `4`. A non-positive or non-integer
    value must raise `ArgumentError`.
  Return the usual `{:ok, pid}`.

- `BoundedRunner.submit(name, task_id, opts)` — registers a task.
  - `opts` is a keyword list with:
    - `:depends_on` — a list of `task_id`s this task depends on. Optional,
      defaults to `[]`.
    - `:func` — a zero-arity function to execute. Required.
  - Returns `:ok`. Submitting the same `task_id` again overwrites the previous
    definition. Nothing runs until `run_all/1` is called.

- `BoundedRunner.run_all(name)` — validates the graph, then executes all tasks.
  - A task's `:func` runs only **after every one of its dependencies has finished
    executing**.
  - At no point may more than `max_concurrency` tasks be executing at once. When
    more tasks are ready than there are free slots, the extras wait; as each
    running task finishes, a free slot is immediately given to a waiting ready
    task (and finishing a task may make new tasks ready by satisfying their
    dependencies).
  - On success it returns `{:ok, results}` where `results` maps each `task_id`
    to the value returned by its `:func`.
  - If the dependency graph contains a cycle, it must **not** execute any task
    and must return `{:error, {:cycle, involved}}`.
  - If any task lists a dependency that was never submitted, it must **not**
    execute any task and must return `{:error, {:unknown_dependencies, missing}}`.
  - Calling `run_all/1` with no submitted tasks returns `{:ok, %{}}`.

## Notes

- Use only the OTP standard library — no external dependencies.
- Give me the complete module in a single file.
- The design goal is correctness of ordering *and* a hard concurrency ceiling:
  with `max_concurrency: 2`, six independent equal-length tasks should take
  roughly three waves, not one; and dependency ordering must still hold exactly.