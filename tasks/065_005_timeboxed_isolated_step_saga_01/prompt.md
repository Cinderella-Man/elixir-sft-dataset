# TimeboxedSaga — Specification

## Context (change request)

Our existing in-process saga coordinator runs every step's forward action
*inline*, in the same process that drives the saga. A misbehaving action — one
that blocks forever on a dead socket, or spins on a hot loop — therefore wedges
the whole coordinator. Compensation never runs, and the caller hangs.

This change request specifies a **new module, `TimeboxedSaga`**, that isolates
each forward action in its **own process** and puts a **deadline** on it. It has
a deliberately different surface from the old builder-style coordinator: there is
no `new/0` and no `step/…` accumulator — a saga is just a plain list of step maps
handed to `run/2` or `run/3`.

Use only the Elixir/OTP standard library. Deliver the complete module in a single
file.

## Vocabulary

- **context** — a map threaded through the steps.
- **step** — a map with these keys:
  - `:name` — an identifier (any term; typically an atom) used as the context key
    for the step's result and as its label in the error report.
  - `:action` — a 1-arity function receiving the current context, returning
    `{:ok, result}` or `{:error, reason}`.
  - `:compensation` — a 1-arity function receiving the current context that undoes
    the step. Its return value is recorded (by convention `{:ok, _}` / `{:error, _}`,
    but any term is allowed).
  - `:timeout` — *optional* per-step deadline in milliseconds for that step's
    action. When absent, the saga's default timeout applies.

## Public API

### `TimeboxedSaga.run(steps, context)`

Equivalent to `run(steps, context, [])`.

### `TimeboxedSaga.run(steps, context, opts)`

Runs the list of `steps` in order, starting from `context`. `opts` is a keyword
list supporting:

- `:default_timeout` — the deadline (in milliseconds) applied to any step that
  does not carry its own `:timeout`. **Default: `5000`.**

## Forward pass

For each step, in list order:

1. The step's **action runs in a separate, isolated process**, not in the
   caller's process. The caller waits for it up to the step's effective deadline
   (its own `:timeout`, else `:default_timeout`).
2. If the action returns `{:ok, result}` before the deadline: store `result` in
   the context under the step's `:name` key (`Map.put(context, name, result)`),
   mark the step **completed**, and continue. Later steps therefore observe
   earlier steps' results in their context.
3. If the action returns `{:error, reason}`: the step **fails** with that
   `reason`; stop the forward pass and begin compensation.
4. If the action **raises or exits**: the step **fails** with error
   `{:crashed, reason}`, where `reason` is the raised exception (or the exit
   reason); stop and begin compensation.
5. If the action returns anything other than `{:ok, _}` or `{:error, _}`: the step
   **fails** with error `{:bad_return, value}`, where `value` is the offending
   return; stop and begin compensation.
6. **Deadline exceeded (timeout).** If the action does not return within the
   effective deadline, the coordinator **kills the action's process** (so its
   in-flight side effects stop) and **ignores any result it might still
   produce** — a late reply must never influence the outcome. The step **fails**
   with error `:timeout`; execution proceeds to compensation exactly as for any
   other failure.

Only the **forward actions** are timeboxed and isolated in their own process;
compensations (below) run in the coordinator itself.

## Compensation pass

When a step fails, run the `:compensation` of every **completed** step in
**reverse completion order** (most-recently-completed first). Each compensation
receives the context as accumulated up to the point of failure — which includes
that step's own stored result, but **not** the failed step's key (the failed step
never completed).

Compensation is **best-effort**:

- If a compensation returns `{:error, _}`, record it and keep going.
- If a compensation **raises**, the coordinator **catches it**, records that
  compensation's value as `{:raised, exception}` (the raised exception), and
  continues with the remaining compensations. A raising compensation must not
  crash the coordinator and must not abort the pass.

The step that **failed** is not "completed", so its compensation is **not** run.

## Return values

- **All steps succeed:** `{:ok, final_context}` — the starting context with every
  step's result merged in under its `:name` key.
- **A step fails:** `{:error, error}`, where `error` is a map with *exactly* these
  four keys:
  - `:step` — the `:name` of the failing step.
  - `:error` — the failure reason: the returned `reason`, or `:timeout`, or
    `{:crashed, reason}`, or `{:bad_return, value}`, per the forward-pass rules.
  - `:compensated` — the list of step names whose compensations ran, in the order
    they ran (reverse of completion order).
  - `:compensations` — a map of `name => compensation_return_value` for each
    compensation that ran (a raising compensation is recorded as
    `{:raised, exception}`).
- **Empty `steps` list:** `{:ok, context}`, unchanged.

## Example

```elixir
steps = [
  %{name: :reserve, action: &reserve/1, compensation: &cancel/1, timeout: 1_000},
  %{name: :charge,  action: &charge/1,  compensation: &refund/1, timeout: 2_000},
  %{name: :ship,    action: &ship/1,    compensation: &unship/1}
]

TimeboxedSaga.run(steps, %{order_id: 42}, default_timeout: 3_000)
```

If `:charge`'s action ran past its 2-second deadline, the result would be:

```elixir
{:error, %{
  step: :charge,
  error: :timeout,
  compensated: [:reserve],
  compensations: %{reserve: {:ok, :cancelled}}
}}
```