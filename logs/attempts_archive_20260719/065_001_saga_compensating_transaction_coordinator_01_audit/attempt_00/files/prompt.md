# Saga / Compensating Transaction Coordinator

Write me an Elixir module called `Saga` that executes a **saga**: a sequence of
steps where each step has a forward **action** and a **compensating action**. If
any step fails, the coordinator undoes the work already done by running the
compensating actions for all previously-completed steps, in reverse order.

Use only the Elixir/OTP standard library — no external dependencies. Give me the
complete module in a single file.

## Public API

The module must support this fluent, pipe-friendly interface:

```elixir
Saga.new()
|> Saga.step(:reserve, &reserve/1, &cancel_reservation/1)
|> Saga.step(:charge,  &charge/1,  &refund/1)
|> Saga.step(:ship,    &ship/1,    &unship/1)
|> Saga.execute(%{order_id: 42})
```

### `Saga.new/0`

Returns a new, empty saga value (any internal representation you like — treat it
as opaque).

### `Saga.step(saga, name, action, compensation)`

Appends a step to the saga and returns the updated saga.

- `name` — an identifier for the step (typically an atom).
- `action` — a 1-arity function that receives the current **context** (a map).
  It must return either:
  - `{:ok, result}` — the step succeeded; or
  - `{:error, reason}` — the step failed.
- `compensation` — a 1-arity function that receives the current context and
  undoes the step's effect. Its return value is recorded (by convention return
  `{:ok, _}` / `{:error, _}`, but any term is allowed).

Steps run in the order they were added.

### `Saga.execute(saga, context)`

Runs the saga starting from the given `context` map.

**Forward pass.** For each step in order, call its `action` with the current
context:

- On `{:ok, result}`: store the result in the context under the step's `name`
  key (i.e. `Map.put(context, name, result)`), mark the step **completed**, and
  continue to the next step. Later steps therefore see the results of earlier
  steps in their context.
- On `{:error, reason}`: stop the forward pass immediately (do **not** run any
  further steps' actions) and begin the compensation pass.

**Compensation pass.** Run the `compensation` of every **completed** step in
**reverse** completion order (most recently completed first). Each compensation
receives the context as accumulated up to the point of failure (which includes
that step's own stored result). Compensation is **best-effort**: if a
compensation returns `{:error, _}`, record it but still run the remaining
compensations.

Note: the step that *failed* is not "completed", so its compensation is **not**
run.

### Return values

- **All steps succeed:** return `{:ok, final_context}`, where `final_context` is
  the starting context with every step's result merged in under its name key.
- **A step fails:** return `{:error, error}` where `error` is a map with exactly
  these keys:
  - `:step` — the `name` of the step whose action returned `{:error, _}`.
  - `:error` — the `reason` from that failing action.
  - `:compensated` — a list of the step names whose compensations were run, in
    the order they ran (i.e. reverse of completion order).
  - `:compensations` — a map of `name => compensation_return_value` for each
    compensation that was run.
- **Empty saga** (no steps): return `{:ok, context}` unchanged.

## Example

```elixir
saga =
  Saga.new()
  |> Saga.step(:a, fn _ctx -> {:ok, 10} end, fn _ctx -> {:ok, :undo_a} end)
  |> Saga.step(:b, fn ctx -> {:ok, ctx.a + 5} end, fn _ctx -> {:ok, :undo_b} end)

Saga.execute(saga, %{})
#=> {:ok, %{a: 10, b: 15}}
```

If step `:b` had instead returned `{:error, :nope}`, the result would be:

```elixir
{:error, %{
  step: :b,
  error: :nope,
  compensated: [:a],
  compensations: %{a: {:ok, :undo_a}}
}}
```