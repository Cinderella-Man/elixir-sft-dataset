Write me an Elixir module called `Pipeline` that lets callers build and run linear processing pipelines from composable stages, where each stage can carry its own **retry policy**.

I need these functions in the public API:
- `Pipeline.new()` — returns a fresh, empty pipeline struct.
- `Pipeline.stage(pipeline, name, fun, opts \\ [])` — appends a named stage to the pipeline. `name` is an atom, `fun` is a one-arity function that receives the current value and returns either `{:ok, result}` or `{:error, reason}`. `opts` may contain:
  - `:retries` — a non-negative integer, the number of *additional* attempts allowed after the first attempt fails (default `0`, i.e. no retries).
  - `:backoff_ms` — a non-negative integer number of milliseconds to sleep between attempts (default `0`).
  Stages must be stored in insertion order.
- `Pipeline.run(pipeline, input)` — executes all stages in order, threading the result of each successful stage as the input to the next.
  - When a stage returns `{:error, reason}` and it still has retries remaining, re-invoke the same stage on the **same input** (after sleeping `:backoff_ms`), up to its retry budget.
  - If a stage eventually succeeds within its budget, continue with the next stage.
  - If a stage exhausts its retry budget, immediately halt and return `{:error, failed_stage_name, reason, attempts}` where `attempts` is the total number of times that stage was invoked (initial try + retries used). Do not execute any subsequent stages.
  - If every stage ultimately succeeds, return `{:ok, final_result, metadata}` where `metadata` is a list of `%{stage: atom, duration_us: non_neg_integer, attempts: pos_integer}` entries in execution order. `duration_us` is the **total** time spent across all attempts of that stage; `attempts` is how many times its function ran.

Timing must be measured with `:timer.tc/1` (or equivalent microsecond-resolution call) and accumulated across attempts.

The module must not use a GenServer or any global state — it is a plain Elixir module that works in the caller's process (using `Process.sleep/1` for backoff is fine). Use only the standard library, no external dependencies. Give me the complete implementation in a single file.