# Heartbeat Monitor

Write me an Elixir module called `Monitor` — a `GenServer` that supervises a set of
registered services by calling a check function for each one on a periodic
interval, tracking each service's status, and firing a notification when a service
goes down. Use only the OTP standard library, no external dependencies, and give me
the complete module in a single file.

## The singleton and its lifecycle

`Monitor` is a singleton process. The convenience functions below
(`register`, `status`, `statuses`, `check_now`) take **no server argument** — they
operate on the process registered under the module name `Monitor`.

- `Monitor.start_link(opts \\ [])` starts and links the process and returns the
  usual `GenServer.on_start()` result. `opts` is a keyword list defaulting to `[]`.
  The process must be registered under the name `Monitor` (i.e. `__MODULE__`) so the
  no-argument convenience API can find it. A `:name` option may override the
  registered name, but the convenience functions always target `Monitor`.
- Starting the server does no monitoring work; a freshly started server tracks zero
  services, and `Monitor.statuses()` returns `%{}`.

## Registering services

`Monitor.register(service_name, check_func, interval_ms, opts \\ [])`

- `service_name` is any term used as the key (strings, atoms, tuples all work and
  are compared by value).
- `check_func` is a **zero-arity** function returning either `:ok` (healthy) or
  `{:error, reason}` (unhealthy), where `reason` is any term.
- `interval_ms` is a **positive integer**: how often, in milliseconds, the monitor
  calls `check_func` after registration.
- `opts` is a keyword list:
  - `:threshold` — a **positive integer** `N`. The service is marked `:down` after
    `N` **consecutive** failed checks. Defaults to `3`.
  - `:notify` — a **two-arity** function `notify.(service_name, reason)` invoked
    when the service transitions from `:up` to `:down` (see below). Defaults to a
    no-op.

`register/4` returns `:ok`.

Guards: `check_func` must be a zero-arity function and `interval_ms` must be a
positive integer. Calling `register` with a non-positive or non-integer
`interval_ms` is outside the contract and may raise `FunctionClauseError` — guard
the public function accordingly.

On registration:

- The service's status starts as `:up` with a consecutive-failure count of `0`.
- Registration itself does **not** run the check function. The first check happens
  one `interval_ms` later, then repeats every `interval_ms` thereafter (implemented
  with `Process.send_after/3`, re-scheduling itself after each check).

Re-registering an already-registered `service_name` **replaces** its configuration
(check function, interval, threshold, notify) and **resets** its status to `:up`
with a failure count of `0`.

### Lifecycle rule for re-registration (important)

When a service is re-registered, the **previous registration's scheduled checks
must never run again**. After a re-registration:

- The old check function is never called again by any leftover/previously-scheduled
  timer.
- Checks for that service happen only at the **new** interval, calling the **new**
  check function.

In other words, superseded timer chains are dead. (A robust way to achieve this is
to tag each registration with a generation token and ignore scheduled check
messages whose token no longer matches the current registration.)

## Performing a check

Each check — whether triggered by the periodic timer or by `check_now/1` below —
does exactly the following, calling `check_func.()` once:

- If the result is `:ok`: the consecutive-failure count is reset to `0`. If the
  service was `:down`, it recovers to `:up`. (Recovery does **not** call the notify
  function — only down transitions do.)
- If the result is `{:error, reason}`: the consecutive-failure count is incremented
  by one.
  - If, as a result, the count **reaches the threshold `N`** and the service's
    current status is `:up`, the service transitions to `:down` and the notify
    function is called **exactly once** as `notify.(service_name, reason)`, where
    `reason` is the reason from this failing check (the `N`-th consecutive
    failure).
  - If the service is **already `:down`**, further failed checks keep it `:down`
    and do **not** call the notify function again.
  - If the count is still below `N`, the status stays `:up`.

"Consecutive" means any `:ok` result resets the counter to zero. A service that
recovers to `:up` and then fails `N` more times in a row transitions to `:down`
again and fires the notify function **again** (once per distinct down transition).

## Deterministic single check

`Monitor.check_now(service_name)` synchronously performs **one** check for the
named service immediately — identical work to a scheduled interval tick (calling
the check function, updating the failure count and status, and firing the notify
function on an `:up` → `:down` transition). It returns `{:ok, status}` where
`status` is the resulting status (`:up` or `:down`), or `{:error, :not_found}` if
no such service is registered. `check_now/1` does not alter or reschedule the
periodic timer.

## Querying status

- `Monitor.status(service_name)` returns `:up` or `:down` for a registered service,
  or `{:error, :not_found}` if the service is unknown.
- `Monitor.statuses()` returns a map `%{service_name => status}` containing every
  currently registered service and its `:up`/`:down` status. With no services
  registered it returns `%{}`.

## Robustness

Any unexpected message sent to the server (anything other than the messages it uses
for its own scheduling) must be ignored: it must not crash the process or alter
state.

Services are fully independent: exhausting failures for one service never affects
another service's status or failure count.