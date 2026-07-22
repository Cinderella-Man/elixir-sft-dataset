Write me an Elixir module called `Saga` that implements the Saga pattern **with composable, nested sub-sagas**. A saga step can be either a plain leaf action or an entire embedded sub-saga, forming a tree. Compensation must unwind that tree correctly.

Public API:
- `Saga.new()` — creates a new, empty saga struct.
- `Saga.step(saga, name, action_fn, compensate_fn)` — appends a **leaf** step. `action_fn` receives the accumulated context and returns `{:ok, result}` or `{:error, reason}`; on success the result is merged into the context under `name`. `compensate_fn` receives the context and its return value is recorded but never fails the chain.
- `Saga.nest(saga, name, sub_saga)` — appends a **nested** step whose behaviour is another `Saga` value. When executed, the sub-saga runs against the current accumulated context; on success its final context is merged into the outer context under `name`.
- `Saga.execute(saga, context)` — runs the steps in order.

Return values:
- `{:ok, final_context}` on full success.
- `{:error, failed_path, reason, compensation_results}` on failure, where:
  - `failed_path` is a list of step names from the outermost saga down to the leaf that actually failed (e.g. `[:child, :y]` when leaf `:y` failed inside nested step `:child`; a top-level leaf failure yields `[:name]`).
  - `compensation_results` is a keyword list `[step_name: value]` in reverse call order.

Failure & compensation semantics:
- When a leaf fails, forward execution stops and previously completed steps of the **current** saga are compensated in reverse order.
- When a **nested** sub-saga fails, it first compensates its own completed inner steps (in reverse), then the failure propagates to the outer saga, which compensates its previously completed steps. The returned `compensation_results` lists the failed nested step's inner compensation results first, as `{nested_name, inner_keyword_list}`, followed by the outer steps in reverse order.
- When compensation reaches a previously **fully-succeeded** nested step, every inner step is compensated in reverse, and its entry in the keyword list is `{nested_name, inner_keyword_list}` (itself in reverse order). Nesting is arbitrarily deep.
- A raising compensating function must not abort the remaining compensations; catch and record it.

Plain module with a struct — no GenServer, no processes, no external dependencies. Give me the complete implementation in a single file.