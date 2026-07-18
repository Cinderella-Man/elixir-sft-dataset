Write me an Elixir module called `Pipeline` that builds and runs linear processing pipelines from composable stages, with support for **fan-out map stages** that process a collection concurrently.

I need these functions in the public API:
- `Pipeline.new()` — returns a fresh, empty pipeline struct.
- `Pipeline.stage(pipeline, name, fun)` — appends a normal **sequential** stage. `name` is an atom; `fun` is a one-arity function that receives the current value and returns `{:ok, result}` or `{:error, reason}`.
- `Pipeline.map_stage(pipeline, name, fun, opts \\ [])` — appends a **fan-out** stage. Its input must be a list. `fun` is a one-arity function applied to **each element** concurrently, returning `{:ok, element_result}` or `{:error, reason}`. `opts` may contain `:max_concurrency` (a positive integer); when omitted, there is no concurrency bound — **every** element runs concurrently at once. Element results must be collected in **input order**. If every element succeeds, the stage's output is the list of element results (threaded to the next stage). If any element fails, the stage fails with the **first** failure by input index, and the `reason` is that element's `{:error, reason}` reason.
- `Pipeline.run(pipeline, input)` — executes all stages in insertion order, threading each stage's output into the next. An empty pipeline returns the input unchanged with empty metadata. On full success return `{:ok, final_result, metadata}` where `metadata` is a list of entries in execution order:
  - sequential stage: `%{stage: atom, duration_us: non_neg_integer, type: :sequential, count: 1}`
  - map stage: `%{stage: atom, duration_us: non_neg_integer, type: :map, count: non_neg_integer}` where `count` is the number of input elements.
  On the first failing stage, immediately halt and return `{:error, failed_stage_name, reason}` — do not run any later stages.

Fan-out concurrency must use `Task.async_stream/3` (or equivalent) with ordered results and the requested `:max_concurrency`. Timing per stage must be measured with `:timer.tc/1` (microsecond resolution). If a map stage receives a non-list input, raise `ArgumentError`.

Use only the standard library, no external dependencies. Give me the complete implementation in a single file.
