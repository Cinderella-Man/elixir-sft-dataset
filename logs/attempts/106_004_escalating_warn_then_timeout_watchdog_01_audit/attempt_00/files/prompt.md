# Escalating (Warn-then-Timeout) Watchdog Timer GenServer

Write me an Elixir GenServer module called `EscalatingWatchdog` that monitors the
liveness of registered processes using a heartbeat mechanism with **two escalation
stages**. Each registration has an early `warn_ms` deadline and a later `timeout_ms`
deadline: if an entity goes quiet, the watchdog first fires a *warning* callback, and
only if it stays quiet longer does it fire the *timeout* callback and give up.

## Public API

- `EscalatingWatchdog.start_link(opts)` — starts the process.
  - Accepts a `:name` option for process registration. If not provided, the server
    registers itself under the name `EscalatingWatchdog` (i.e. `__MODULE__`), because all
    other API functions target that fixed registered name and take no server argument.
  - Returns `{:ok, pid}` (standard `GenServer.start_link/3` return).

- `EscalatingWatchdog.register(name, pid, warn_ms, timeout_ms, on_warn_fn, on_timeout_fn)`
  — begins monitoring an entity identified by `name` (any term).
  - `pid` is the process associated with this registration; record it, but the watchdog
    is **not** required to monitor the pid for `:DOWN`/exit events — liveness is
    determined purely by heartbeats.
  - `warn_ms` and `timeout_ms` are millisecond deadlines measured from the last
    heartbeat (or from registration). `warn_ms` **must be strictly less than**
    `timeout_ms`; otherwise the call raises `ArgumentError`.
  - `on_warn_fn` and `on_timeout_fn` are each **one-argument** functions, invoked as
    `on_warn_fn.(name)` and `on_timeout_fn.(name)` respectively.
  - The clock starts immediately. With no heartbeat, `on_warn_fn.(name)` fires at
    `warn_ms` (once), and `on_timeout_fn.(name)` fires at `timeout_ms`, after which the
    registration is removed.
  - Registering a `name` that is already registered **replaces** the previous
    registration entirely (new pid, deadlines, callbacks, phase reset, and freshly armed
    timers).
  - Returns `:ok`, synchronously — once it returns, both timers are armed.

- `EscalatingWatchdog.heartbeat(name)` — records a heartbeat for `name`, resetting **both**
  deadlines (a fresh `warn_ms` and `timeout_ms`) and returning the phase to `:healthy`.
  A heartbeat after a warning re-arms everything, so the warning can fire again later.
  - Calling `heartbeat/1` for an unregistered `name` is a harmless no-op.
  - Returns `:ok`, synchronously.

- `EscalatingWatchdog.phase(name)` — returns `{:ok, :healthy}` before the warning has
  fired, `{:ok, :warned}` after the warning has fired but before the timeout, or
  `{:error, :not_registered}` for an unknown name (including after a timeout has removed
  the registration).

- `EscalatingWatchdog.unregister(name)` — stops monitoring `name`. After this returns,
  neither the warning nor the timeout callback may fire for that `name`. Unregistering an
  unknown `name` is a no-op. Returns `:ok`.

## Escalation semantics

- Within a single silent window, `on_warn_fn.(name)` fires **at most once** (at
  `warn_ms`) and `on_timeout_fn.(name)` fires **at most once** (at `timeout_ms`), after
  which the registration is removed.
- A heartbeat resets the escalation: a heartbeat before `warn_ms` prevents the warning
  in that window; a heartbeat after the warning but before the timeout cancels the
  pending timeout and re-arms a fresh warn/timeout pair (so the warning can recur).
- Each registration is independent: escalation for one `name` must have no effect on any
  other `name`.

## Implementation notes

- Use `Process.send_after/3` (or `:timer`) to schedule the warn and timeout deadlines,
  and guard against stale timers (e.g. by tagging each armed generation with a reference)
  so a reset or unregister cannot let an old timer fire.
- Give me the complete module in a single file. Use only the OTP standard library,
  no external dependencies.