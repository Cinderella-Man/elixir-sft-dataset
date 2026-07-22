# Data-Flow Task Dependency Resolver

Write me an Elixir `GenServer` module called `DataFlowRunner` that accepts tasks
with dependencies and executes them in a valid order, running independent tasks
concurrently — **and threads each task's dependency results into that task's
function as input**. Unlike a plain runner where every function is zero-arity and
self-contained, here a task's function receives the outputs of the tasks it
depends on, so data flows down the DAG.

## Public API

- `DataFlowRunner.start_link(opts)` — starts the process. It must accept a `:name`
  option used for process registration (so the process can be referred to by an
  atom name in the other functions). Return the usual `{:ok, pid}`.

- `DataFlowRunner.submit(name, task_id, opts)` — registers a task with the runner.
  - `name` is the registered process name.
  - `task_id` is any term that uniquely identifies the task (typically an atom).
  - `opts` is a keyword list with:
    - `:depends_on` — a list of `task_id`s this task depends on. Optional,
      defaults to `[]`.
    - `:func` — a **one-arity** function. Required. It is called with a map
      `%{dep_id => result}` containing the return value of each of this task's
      **direct** dependencies. A task with no dependencies receives `%{}`.
  - Returns `:ok`. Submitting the same `task_id` again overwrites the previous
    definition. Tasks are only *registered* by `submit/3`; nothing runs until
    `run_all/1` is called. If `:func` is not a one-arity function, raise
    `ArgumentError`.

- `DataFlowRunner.run_all(name)` — validates the dependency graph, then executes
  all submitted tasks.
  - It must perform a topological sort so that a task's `:func` only begins
    executing **after every one of its dependencies has finished executing**, and
    only then with those dependencies' results as its input map.
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
- The design goal is correctness of ordering, real parallelism, *and* correct
  data flow: each function must observe exactly the results of the tasks it
  declared as dependencies.