Write me an Elixir module called `Saga` that implements the Saga pattern **with a pivot boundary and forward recovery**. Unlike a plain saga where every failure rolls everything back, this coordinator distinguishes two kinds of steps:

- **Compensable steps** — added with `Saga.step(saga, name, action_fn, compensate_fn)`. These come *before* the commit point and can be rolled back.
- **Retriable steps** — added with `Saga.retriable(saga, name, action_fn, max_attempts)`. These come *after* the commit point. They have no compensating action; instead, if the action fails it is retried (re-invoked with the same context) up to `max_attempts` total attempts. Retriable steps model post-commit work that must be driven *forward* to completion, not undone.

Public API:
- `Saga.new()` — creates a new, empty saga struct.
- `Saga.step(saga, name, action_fn, compensate_fn)` — appends a compensable step. `action_fn` is a 1-arity function receiving the context map and returning `{:ok, result}` or `{:error, reason}`. `compensate_fn` is a 1-arity function receiving the context; its return value is recorded but never fails the compensation chain.
- `Saga.retriable(saga, name, action_fn, max_attempts)` — appends a retriable step. `max_attempts` is a positive integer; reject a non-positive value with a guard clause, so passing `0` or a negative number raises `FunctionClauseError`.
- `Saga.execute(saga, context)` — runs all steps in order, threading the context map (a successful step's result is merged under its name). On success, returns `{:ok, final_context}` — the accumulated context map (the original context for an empty saga).

Failure semantics:
- If a **compensable** step returns `{:error, reason}`, forward execution stops and the compensating actions of all previously completed **compensable** steps run in **reverse order**. Return `{:error, failed_step_name, reason, compensation_results}`, where `compensation_results` is a keyword list of `[step_name: compensate_return_value]` in reverse call order. Retriable steps are never compensated (they are post-commit).
- A **retriable** step that returns `{:error, reason}` is retried, re-invoking its action with the same context, until it returns `{:ok, result}` or `max_attempts` attempts have been made. On exhaustion, return `{:error, failed_step_name, {:retries_exhausted, last_reason}, []}` — note the empty compensation list, because committed compensable steps are **not** rolled back once the pivot has been crossed. `last_reason` is the reason from the final attempt.

Other behaviours to preserve:
- Steps run strictly in the order added; each action/compensation sees the accumulated context.
- A raising compensating function must not abort the remaining compensations; catch and record it (its recorded value may be any term).
- Plain module with a struct — no GenServer, no processes, no external dependencies.

Give me the complete implementation in a single file.
