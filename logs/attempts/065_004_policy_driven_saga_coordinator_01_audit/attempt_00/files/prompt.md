# Policy-Driven Saga / Compensating Transaction Coordinator

Write me an Elixir module called `PolicySaga` that executes a **saga** — a sequence of
steps, each with a forward **action** and a **compensating action** — with a
configurable **rollback policy** per step. As in a normal saga, if a step's action
fails, the coordinator runs the compensations of previously-completed steps in reverse
order. The twist: a step can declare that if **its own compensation fails**, the whole
rollback must **abort** (stop immediately, leaving the remaining earlier steps
uncompensated for manual intervention) rather than continuing best-effort.

Use only the Elixir/OTP standard library — no external dependencies. Give me the
complete module in a single file.

## Public API

```elixir
PolicySaga.new()
|> PolicySaga.step(:reserve, &reserve/1, &cancel/1, on_error: :abort)
|> PolicySaga.step(:charge,  &charge/1,  &refund/1)
|> PolicySaga.execute(%{order_id: 42})
```

### `PolicySaga.new/0`

Returns a new, empty saga value (opaque).

### `PolicySaga.step(saga, name, action, compensation, opts \\ [])`

Appends a step and returns the updated saga.

- `name` — an identifier for the step.
- `action` — a 1-arity function receiving the current **context** (a map), returning
  `{:ok, result}` or `{:error, reason}`.
- `compensation` — a 1-arity function receiving the context that undoes the step; its
  return value is recorded. By convention it returns `{:ok, _}` (success) or
  `{:error, _}` (failed to compensate).
- `opts` — supports `:on_error`, the step's rollback policy, one of:
  - `:continue` (default) — if this step's compensation returns `{:error, _}`, record
    it and keep running the remaining compensations (best-effort).
  - `:abort` — if this step's compensation returns `{:error, _}`, stop the whole
    rollback immediately; earlier steps are left uncompensated.

Any other `:on_error` value must raise `ArgumentError`. Steps run in the order added.

### `PolicySaga.execute(saga, context)`

**Forward pass.** For each step in order, call its `action`:

- On `{:ok, result}`: store under the step's `name` key, mark the step **completed**,
  continue.
- On `{:error, reason}`: stop the forward pass and begin compensation.

**Compensation pass.** Run the compensations of the completed steps in reverse
completion order (most recently completed first). Each compensation receives the
context accumulated up to the point of failure. For each compensation that returns
`{:error, _}`: if that step's policy is `:abort`, stop the pass immediately (the
compensations *not yet run* are left uncompensated); otherwise record and continue.
The failed step's compensation is not run.

### Return values

- **All steps succeed:** `{:ok, final_context}`.
- **A step fails:** `{:error, error}` where `error` has exactly these keys:
  - `:step` — the `name` of the failing step.
  - `:error` — the `reason` from the failing action.
  - `:compensated` — the list of step names whose compensations ran (were attempted),
    in run order.
  - `:compensations` — a map `name => compensation_return_value`.
  - `:aborted_at` — the `name` of the compensation whose failure aborted the rollback,
    or `nil` if the pass completed normally.
  - `:uncompensated` — the list of completed step names that were *not* compensated
    because the rollback aborted, in the order they would have run (`[]` if none).
- **Empty saga:** `{:ok, context}` unchanged.