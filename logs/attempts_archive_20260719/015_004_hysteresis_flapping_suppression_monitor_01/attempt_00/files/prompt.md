# Hysteresis Flapping-Suppression Monitor

Write me an Elixir module called `StabilityMonitor` — a `GenServer` that supervises
registered services by calling a check function for each one on a periodic interval,
and reports a **confirmed** `:up`/`:down` state that changes only after the service
has been consistently failing (or consistently recovering) for a configured number
of checks. This hysteresis suppresses "flapping" — a service that alternates between
success and failure never changes its confirmed state. Use only the OTP standard
library, no external dependencies, and give me the complete module in a single file.

## The singleton and its lifecycle

`StabilityMonitor` is a singleton process. The convenience functions below
(`watch`, `force_check`, `state`, `states`, `unwatch`) take **no server argument** —
they operate on the process registered under the module name `StabilityMonitor`.

- `StabilityMonitor.start_link(opts \\ [])` starts and links the process and returns
  the usual `GenServer.on_start()` result. `opts` is a keyword list defaulting to
  `[]`. The process must be registered under the name `StabilityMonitor` (i.e.
  `__MODULE__`) so the no-argument convenience API can find it. A `:name` option may
  override the registered name, but the convenience functions always target
  `StabilityMonitor`.
- Starting the server does no monitoring work; a freshly started server tracks zero
  services, and `StabilityMonitor.states()` returns `%{}`.

## Registering services

`StabilityMonitor.watch(name, check_func, interval_ms, opts \\ [])`

- `name` is any term used as the key (strings, atoms, tuples all work and are
  compared by value).
- `check_func` is a **zero-arity** function returning either `:ok` (healthy) or
  `{:error, reason}` (unhealthy), where `reason` is any term.
- `interval_ms` is a **positive integer**: how often, in milliseconds, the monitor
  calls `check_func` after registration.
- `opts` is a keyword list:
  - `:fail_confirm` — a **positive integer** `F`: the number of **consecutive**
    failures required to confirm a transition to `:down`. Defaults to `3`.
  - `:ok_confirm` — a **positive integer** `K`: the number of **consecutive**
    successes required to confirm a transition back to `:up`. Defaults to `2`.
  - `:on_transition` — a **three-arity** function
    `on_transition.(name, from_state, to_state)` invoked whenever the confirmed
    state changes (see below). Defaults to a no-op.

`watch/4` returns `:ok`.

Guards: `check_func` must be a zero-arity function and `interval_ms` must be a
positive integer. Calling `watch` with a non-positive or non-integer `interval_ms`,
or a check function of the wrong arity, is outside the contract and raises
`FunctionClauseError`; guard the public function accordingly.

On registration:

- The service's confirmed state starts as `:up`, with a failure streak of `0` and a
  success streak of `0`.
- Registration itself does **not** run the check function. The first check happens
  one `interval_ms` later, then repeats every `interval_ms` thereafter (implemented
  with `Process.send_after/3`, re-scheduling itself after each check).

Re-watching an already-registered `name` **replaces** its configuration (check
function, interval, confirmations, on_transition) and **resets** its confirmed state
to `:up` with both streaks at `0`.

### Lifecycle rule for re-watching (important)

When a service is re-watched, the **previous registration's scheduled checks must
never run again**. After a re-watch:

- The old check function is never called again by any leftover/previously-scheduled
  timer.
- Checks for that service happen only at the **new** interval, calling the **new**
  check function.

Superseded timer chains are dead. (A robust way to achieve this is to tag each
registration with a generation token and ignore scheduled check messages whose token
no longer matches the current registration.)

## Performing a check

Each check — whether triggered by the periodic timer or by `force_check/1` below —
calls `check_func.()` exactly once and then updates the service using two counters,
a failure streak and a success streak:

- On `:ok`:
  - The failure streak is reset to `0`.
  - If the confirmed state is currently `:down`, the success streak is incremented
    by one. If it then **reaches** `ok_confirm`, the confirmed state transitions to
    `:up`, `on_transition.(name, :down, :up)` is called **exactly once**, and the
    success streak is reset to `0`. Otherwise the confirmed state stays `:down`.
  - If the confirmed state is currently `:up`, the success streak is reset to `0`
    (a healthy check simply keeps a healthy service up; no callback fires).

- On `{:error, _reason}`:
  - The success streak is reset to `0`.
  - If the confirmed state is currently `:up`, the failure streak is incremented by
    one. If it then **reaches** `fail_confirm`, the confirmed state transitions to
    `:down`, `on_transition.(name, :up, :down)` is called **exactly once**, and the
    failure streak is reset to `0`. Otherwise the confirmed state stays `:up`.
  - If the confirmed state is currently `:down`, the failure streak is reset to `0`
    (a failing check simply keeps a down service down; no callback fires).

Because a result opposite to the current confirmed state resets the streak that was
building toward the current state, **alternating** results (a failure, then a
success, then a failure, …) never accumulate enough in a row to confirm a transition:
the confirmed state stays put and `on_transition` never fires. A confirmed transition
fires `on_transition` exactly once, and going down, then up, then down again fires it
once per confirmed change.

## Deterministic single check

`StabilityMonitor.force_check(name)` synchronously performs **one** check for the
named service immediately — identical work to a scheduled interval tick (calling the
check function, updating the streaks and confirmed state, and firing `on_transition`
on a confirmed change). It returns `{:ok, state}` where `state` is the resulting
confirmed state (`:up` or `:down`), or `{:error, :not_found}` if no such service is
registered. `force_check/1` does not alter or reschedule the periodic timer.

## Querying and removing

- `StabilityMonitor.state(name)` returns the confirmed state `:up` or `:down` for a
  registered service, or `{:error, :not_found}` if the service is unknown.
- `StabilityMonitor.states()` returns a map `%{name => state}` containing every
  currently registered service and its confirmed `:up`/`:down` state. With no
  services registered it returns `%{}`.
- `StabilityMonitor.unwatch(name)` removes a service. It returns `:ok` if the service
  existed (after removal it no longer appears in `states/0` and `state/1` returns
  `{:error, :not_found}`), or `{:error, :not_found}` if no such service was
  registered. After removal the service's scheduled checks must never run again — its
  timer chain is dead.

## Robustness

Any unexpected message sent to the server (anything other than the messages it uses
for its own scheduling) must be ignored: it must not crash the process or alter
state.

Services are fully independent: driving one service's streaks never affects another
service's confirmed state or counters.