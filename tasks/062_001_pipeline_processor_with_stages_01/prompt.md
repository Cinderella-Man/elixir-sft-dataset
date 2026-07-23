I need you to write me an Elixir module called `Pipeline` that lets callers build and run linear processing pipelines out of composable stages. Here's what I need from the public API.

`Pipeline.new()` should hand back a fresh, empty pipeline struct.

`Pipeline.stage(pipeline, name, fun)` appends a named stage to the pipeline and returns a new pipeline — the original has to stay untouched, because I want to be able to branch and reuse a base pipeline. `name` is an atom, and `fun` is a one-arity function that receives the current value and returns either `{:ok, result}` or `{:error, reason}`. Please guard the arguments so that a non-atom `name` or a function of the wrong arity raises `FunctionClauseError`. Stages need to be stored in insertion order, and duplicate names are fine — each occurrence should run.

`Pipeline.run(pipeline, input)` executes all stages in order, threading the result of each stage in as the input to the next. When every stage succeeds, I want back `{:ok, final_result, metadata}`, where `metadata` is a list of `%{stage: atom, duration_us: non_neg_integer}` entries in execution order. A pipeline with no stages returns `{:ok, input, []}`. If any stage returns `{:error, reason}`, halt right there and return `{:error, failed_stage_name, reason}` — don't execute any of the subsequent stages, and pass `reason` back verbatim no matter what shape it has.

Time each stage with `:timer.tc/1` (or an equivalent microsecond-resolution call); each metadata entry's `duration_us` is a non-negative integer. Metadata only shows up in the success tuple — the `{:error, failed_stage_name, reason}` halt result carries no metadata list.

Keep the module pure: no processes, no GenServer, no global state. It should be a plain Elixir module whose stages run entirely in the caller's process, so repeated runs of the same pipeline are independent of each other.

Send me the complete implementation in a single file, standard library only, no external dependencies.
