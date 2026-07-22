# Retrying Saga / Compensating Transaction Coordinator

Write me an Elixir module called `RetrySaga` that executes a **saga** — a sequence
of steps, each with a forward **action** and a **compensating action** — but where
each step's action may be **retried** a configurable number of times before it is
considered failed. Only after a step exhausts its attempts does the coordinator undo
the work already done by running the compensating actions of all previously-completed
steps, in reverse completion order.

Use only the Elixir/OTP standard library — no external dependencies. Give me the
complete module in a single file.

## Public API

```elixir
RetrySaga.new()
|> RetrySaga.step(:reserve, &reserve/1, &cancel/1, max_attempts: 3)
|> RetrySaga.step(:charge,  &charge/1,  &refund/1)
|> RetrySaga.execute(%{order_id: 42})
```

### `RetrySaga.new/0`

Returns a new, empty saga value (opaque).

### `RetrySaga.step(saga, name, action, compensation, opts \\ [])`

Appends a step and returns the updated saga.

- `name` — an identifier for the step (typically an atom).
- `action` — a 1-arity function receiving the current **context** (a map). It must
  return `{:ok, result}` (success) or `{:error, reason}` (this attempt failed).
- `compensation` — a 1-arity function receiving the current context that undoes the
  step's effect. Its return value is recorded (by convention `{:ok, _}` / `{:error, _}`).
- `opts` — currently supports `:max_attempts`, a **positive integer** (default `1`)
  giving the total number of times the action may be tried. Any other value must
  raise `ArgumentError`.

Steps run in the order they were added.

### `RetrySaga.execute(saga, context)`

**Forward pass.** For each step in order, call its `action` with the current context:

- On `{:ok, result}`: store the result under the step's `name` key
  (`Map.put(context, name, result)`), mark the step **completed**, and continue.
- On `{:error, reason}`: if the step has attempts remaining, call the action **again**
  with the *same* context (retry). When `max_attempts` attempts have all returned
  `{:error, _}`, stop the forward pass and begin compensation. Retrying never runs a
  later step's action before the current step succeeds or is exhausted.

**Compensation pass.** Run the `compensation` of every **completed** step in reverse
completion order (most recently completed first). Each compensation receives the
context accumulated up to the point of failure. Compensation is **best-effort**: an
`{:error, _}` return is recorded but the remaining compensations still run. The failed
step is not "completed", so its compensation is not run.

### Return values

- **All steps succeed:** `{:ok, final_context}` (start context with every step's
  result merged in under its name key).
- **A step fails (after exhausting attempts):** `{:error, error}` where `error` has
  exactly these keys:
  - `:step` — the `name` of the failing step.
  - `:error` — the `reason` from the last failing attempt.
  - `:attempts` — the number of attempts actually made on the failing step.
  - `:compensated` — the list of step names whose compensations ran, in run order.
  - `:compensations` — a map of `name => compensation_return_value`.
- **Empty saga:** `{:ok, context}` unchanged.

## Example

```elixir
saga =
  RetrySaga.new()
  |> RetrySaga.step(:a, flaky_twice_then_ok, fn _ -> {:ok, :undo_a} end, max_attempts: 3)
  |> RetrySaga.step(:b, always_fails, fn _ -> {:ok, :undo_b} end, max_attempts: 2)

RetrySaga.execute(saga, %{})
#=> {:error, %{
#     step: :b, error: :nope, attempts: 2,
#     compensated: [:a], compensations: %{a: {:ok, :undo_a}}
#   }}
```