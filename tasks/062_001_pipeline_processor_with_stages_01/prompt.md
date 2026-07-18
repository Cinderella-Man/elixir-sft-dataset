Write me an Elixir module called `Pipeline` that lets callers build and run linear processing pipelines from composable stages.

I need these functions in the public API:
- `Pipeline.new()` — returns a fresh, empty pipeline struct.
- `Pipeline.stage(pipeline, name, fun)` — appends a named stage to the pipeline and returns a new pipeline, leaving the original unchanged so a base pipeline can be branched and reused. `name` is an atom, `fun` is a one-arity function that receives the current value and returns either `{:ok, result}` or `{:error, reason}`. Guard the arguments so that a non-atom `name` or a function of the wrong arity raises `FunctionClauseError`. Stages must be stored in insertion order (duplicate names are allowed and each occurrence runs).
- `Pipeline.run(pipeline, input)` — executes all stages in order, threading the result of each stage as the input to the next. If every stage succeeds, return `{:ok, final_result, metadata}` where `metadata` is a list of `%{stage: atom, duration_us: non_neg_integer}` entries in execution order. A pipeline with no stages returns `{:ok, input, []}`. If any stage returns `{:error, reason}`, immediately halt and return `{:error, failed_stage_name, reason}` — do not execute any subsequent stages, and return `reason` verbatim regardless of its shape.

Timing per stage must be measured with `:timer.tc/1` (or equivalent microsecond-resolution call); each metadata entry's `duration_us` is a non-negative integer. Metadata is returned only in the success tuple — the `{:error, failed_stage_name, reason}` halt result carries no metadata list.

The module must be pure — no processes, no GenServer, no global state. It should be a plain Elixir module whose stages run entirely in the caller's process, so repeated runs of the same pipeline are independent.

Give me the complete implementation in a single file. Use only the standard library, no external dependencies.
