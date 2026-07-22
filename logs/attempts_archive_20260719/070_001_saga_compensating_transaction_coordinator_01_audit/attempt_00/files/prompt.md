Write me an Elixir module called `Saga` that implements the Saga pattern for coordinating distributed transactions with automatic compensation on failure.

I need these functions in the public API:
- `Saga.new()` — creates a new, empty saga struct
- `Saga.step(saga, name, action_fn, compensate_fn)` — appends a named step to the saga. `action_fn` is a 1-arity function that receives the context map and returns either `{:ok, result}` or `{:error, reason}`. `compensate_fn` is a 1-arity function that receives the context map and returns any value (its result is recorded but never fails the compensation chain)
- `Saga.execute(saga, context)` — runs all steps in order, threading a context map through each step. When a step succeeds, merge its result into the context under the step's name (e.g. `%{reserve: result_value}`) and pass the enriched context to the next step. If a step fails, immediately stop forward execution and run the compensating actions for all previously completed steps in **reverse order**, passing the enriched context at the point of failure to each compensating function. Return `{:ok, final_context}` on full success, or `{:error, failed_step_name, reason, compensation_results}` on failure, where `compensation_results` is a keyword list of `[step_name: compensate_return_value]` in the reverse order they were called.

Key behaviours to preserve:
- Steps are executed strictly in the order they were added
- The context passed to each action and compensating function reflects all results accumulated so far — compensating functions receive the full context at the point of failure, not the original one
- A failure in a compensating function must **not** abort the remaining compensations; all compensations must always run and their results (including any exceptions caught) must be recorded
- This is a plain module with a struct — no GenServer, no processes, no external dependencies

Give me the complete implementation in a single file.