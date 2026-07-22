# Parallel-Stage Saga / Compensating Transaction Coordinator

Write me an Elixir module called `ParallelSaga` that executes a **staged saga**. The
saga is built from a series of **stages**; each stage contains one or more steps, and
all steps **within a stage run concurrently**. Every step has a forward **action** and
a **compensating action**. If any step in a stage fails, the coordinator undoes the
work already done — the succeeded steps of the failing stage plus every step of all
earlier stages — by running their compensating actions, and returns an error.

Use only the Elixir/OTP standard library (`Task` is allowed) — no external
dependencies. Give me the complete module in a single file.

## Public API

```elixir
ParallelSaga.new()
|> ParallelSaga.stage([
     {:reserve, &reserve/1, &cancel/1},
     {:notify,  &notify/1,  &unnotify/1}
   ])
|> ParallelSaga.stage([
     {:charge, &charge/1, &refund/1}
   ])
|> ParallelSaga.execute(%{order_id: 42})
```

### `ParallelSaga.new/0`

Returns a new, empty saga value (opaque).

### `ParallelSaga.stage(saga, steps)`

Appends a stage and returns the updated saga. `steps` is a list of
`{name, action, compensation}` tuples:

- `name` — an identifier for the step.
- `action` — a 1-arity function receiving the current **context** (a map), returning
  `{:ok, result}` or `{:error, reason}`.
- `compensation` — a 1-arity function receiving the context that undoes the step.

`action` and `compensation` must both be arity-1 functions, otherwise raise
`ArgumentError`. Stages run in the order added.

### `ParallelSaga.execute(saga, context)`

For each stage in order:

- Start **all** of the stage's actions concurrently, each receiving the **same**
  context — the context as it was at the start of the stage. (Steps in the same stage
  therefore cannot see each other's results; only later stages see a stage's results.)
- Await all actions.
  - If every action returns `{:ok, result}`: merge each result into the context under
    its `name` key and proceed to the next stage.
  - If **any** action returns `{:error, reason}`: the stage fails. Begin compensation.

**Compensation pass.** Run the compensations of every step that must be undone, in
this order: first the **succeeded** steps of the failing stage (in reverse of their
declared order within the stage), then every earlier stage (most recent stage first,
each stage's steps in reverse declared order). The failed step(s) are *not* compensated
(their actions did not succeed). Each compensation receives the context accumulated up
to the point of failure (including the failing stage's succeeded results). Compensation
is best-effort: errors are recorded but do not stop the pass.

### Return values

- **All stages succeed:** `{:ok, final_context}`.
- **A stage fails:** `{:error, error}` where `error` has exactly these keys:
  - `:stage` — the 0-based index of the failing stage.
  - `:failed` — a map `name => reason` for every step in that stage whose action
    returned `{:error, _}` (there may be more than one).
  - `:compensated` — the list of step names whose compensations ran, in run order.
  - `:compensations` — a map `name => compensation_return_value`.
- **Empty saga:** `{:ok, context}` unchanged.