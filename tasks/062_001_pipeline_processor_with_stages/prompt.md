Write me an Elixir module called `Pipeline` that lets callers build and run linear processing pipelines from composable stages.

I need these functions in the public API:
- `Pipeline.new()` — returns a fresh, empty pipeline struct.
- `Pipeline.stage(pipeline, name, fun)` — appends a named stage to the pipeline. `name` is an atom, `fun` is a one-arity function that receives the current value and returns either `{:ok, result}` or `{:error, reason}`. Stages must be stored in insertion order.
- `Pipeline.run(pipeline, input)` — executes all stages in order, threading the result of each stage as the input to the next. If every stage succeeds, return `{:ok, final_result, metadata}` where `metadata` is a list of `%{stage: atom, duration_us: non_neg_integer}` entries in execution order. If any stage returns `{:error, reason}`, immediately halt and return `{:error, failed_stage_name, reason}` — do not execute any subsequent stages.

Timing per stage must be measured with `:timer.tc/1` (or equivalent microsecond-resolution call) and included in the metadata even for a pipeline that halts early — include timing only for the stages that were actually executed.

The module must be pure — no processes, no GenServer, no global state. It should be a plain Elixir module that works entirely in the caller's process.

Give me the complete implementation in a single file. Use only the standard library, no external dependencies.