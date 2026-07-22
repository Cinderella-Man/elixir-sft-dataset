Write me an Elixir module called `Pipeline` that builds linear stage pipelines and runs them over a **batch** of inputs, collecting successes and failures independently instead of halting the whole run on the first error.

I need these functions in the public API:
- `Pipeline.new()` — returns a fresh, empty pipeline struct.
- `Pipeline.stage(pipeline, name, fun)` — appends a named stage. `name` is an atom; `fun` is a one-arity function that receives the current value and returns `{:ok, result}` or `{:error, reason}`. Stages are stored in insertion order.
- `Pipeline.run(pipeline, inputs)` — `inputs` is a **list** of items. Each item is threaded **independently** through all stages in order. If an item's stage returns `{:error, reason}`, that item halts (its later stages are skipped) and is recorded as a failure, but the batch continues processing the remaining items. Return `{:ok, report}` where `report` is a map:
  - `:successes` — a list of `%{index: non_neg_integer, result: term}` for items that completed every stage, ordered by input index.
  - `:failures` — a list of `%{index: non_neg_integer, stage: atom, reason: term}` for items that halted, ordered by input index.
  - `:stage_stats` — a list, in pipeline stage order, of `%{stage: atom, executions: non_neg_integer, total_duration_us: non_neg_integer}` where `executions` counts how many items actually ran that stage (items that halted earlier never reach it) and `total_duration_us` is the summed `:timer.tc/1` microseconds across those executions.

An empty pipeline treats every item as an immediate success whose `result` is the input itself, and produces an empty `:stage_stats`. An empty `inputs` list yields empty `:successes` and `:failures`, with each stage's `executions` at `0`.

The module must not use a GenServer or any global state — it is a plain Elixir module working in the caller's process. Timing must use `:timer.tc/1` (microsecond resolution). Use only the standard library, no external dependencies. Give me the complete implementation in a single file.