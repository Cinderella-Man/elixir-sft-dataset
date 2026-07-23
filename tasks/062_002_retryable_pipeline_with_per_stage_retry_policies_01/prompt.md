**Ticket:** Implement `Pipeline` — a single-file Elixir module for building and running linear processing pipelines from composable stages, where each stage carries its own **retry policy**.

**Public API — `Pipeline.new()`**
- Returns a fresh, empty pipeline struct.

**Public API — `Pipeline.stage(pipeline, name, fun, opts \\ [])`**
- Appends a named stage to the pipeline.
- `name` is an atom.
- `fun` is a one-arity function that receives the current value and returns either `{:ok, result}` or `{:error, reason}`.
- Enforce both with guard clauses: calling `stage/4` with a non-atom `name`, or with a `fun` whose arity is not 1, must raise `FunctionClauseError`.
- `opts` may contain:
  - `:retries` — non-negative integer; the number of *additional* attempts allowed after the first attempt fails. Default `0` (no retries).
  - `:backoff_ms` — non-negative integer number of milliseconds to sleep between attempts. Default `0`.
- Stages are stored in insertion order.
- The same `name` may be used more than once; each such stage is kept and executed as its own step, in insertion order.

**Public API — `Pipeline.run(pipeline, input)`**
- Executes all stages in order, threading the result of each successful stage as the input to the next.
- Empty pipeline returns `{:ok, input, []}` — input unchanged, empty metadata.
- On `{:error, reason}` from a stage that still has retries remaining: re-invoke the same stage on the **same input** (after sleeping `:backoff_ms`), up to its retry budget.
- If a stage eventually succeeds within its budget, continue with the next stage.
- If a stage exhausts its retry budget: immediately halt and return `{:error, failed_stage_name, reason, attempts}`, where `attempts` is the total number of times that stage was invoked (initial try + retries used). Do not execute any subsequent stages.
- If every stage ultimately succeeds: return `{:ok, final_result, metadata}`, where `metadata` is a list of `%{stage: atom, duration_us: non_neg_integer, attempts: pos_integer}` entries in execution order.
- `duration_us` is the **total** time spent across all attempts of that stage; `attempts` is how many times its function ran.

**Timing**
- Measure with `:timer.tc/1` (or equivalent microsecond-resolution call).
- Accumulate across attempts.

**Constraints**
- No GenServer, no global state — plain Elixir module running in the caller's process (`Process.sleep/1` for backoff is fine).
- Standard library only; no external dependencies.
- Deliver the complete implementation in a single file.
