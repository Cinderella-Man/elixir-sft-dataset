# Watchdog Timer GenServer

Write me an Elixir GenServer module called `Watchdog` that monitors the liveness of
registered processes using a heartbeat mechanism. Each monitored entity is expected
to periodically "check in". If it fails to check in within its configured interval,
the `Watchdog` invokes a user-supplied timeout callback.

## Public API

- `Watchdog.start_link(opts)` — starts the process.
  - Accepts a `:name` option for process registration. If not provided, the server
    must register itself under the name `Watchdog` (i.e. `__MODULE__`), because all
    other API functions target that fixed registered name and take no server argument.
  - Returns `{:ok, pid}` (standard `GenServer.start_link/3` return).

- `Watchdog.register(name, pid, interval_ms, on_timeout_fn)` — begins monitoring an
  entity identified by `name` (any term).
  - `pid` is the process associated with this registration; record it (a correct
    callback may capture and use it), but the `Watchdog` is **not** required to monitor
    the pid for `:DOWN`/exit events — liveness is determined purely by heartbeats.
  - `interval_ms` is the maximum time (in milliseconds) allowed between heartbeats.
  - `on_timeout_fn` is a **one-argument** function. When a timeout fires the `Watchdog`
    must invoke it as `on_timeout_fn.(name)`.
  - Registering a `name` that is already registered **replaces** the previous
    registration entirely (new pid, interval, callback, and a freshly armed timer).
  - The clock starts immediately on registration: if no heartbeat arrives within
    `interval_ms` of registering, the timeout fires.
  - Returns `:ok`. This call must be synchronous — once it returns, the timer is armed.

- `Watchdog.heartbeat(name)` — records a heartbeat for `name`, resetting its timer so
  the entity has another full `interval_ms` before it is considered timed out.
  - Calling `heartbeat/1` for a `name` that is not currently registered is a harmless
    no-op.
  - Returns `:ok`. This call must be synchronous so that a heartbeat issued before a
    sleep is guaranteed to have reset the timer.

- `Watchdog.unregister(name)` — stops monitoring `name`. After this returns, no timeout
  callback may fire for that `name` (any already-scheduled timer must be effectively
  cancelled/ignored). Unregistering an unknown `name` is a no-op. Returns `:ok`.

## Timeout semantics

- A timeout is **one-shot**: when a registration times out, the `Watchdog` invokes
  `on_timeout_fn.(name)` exactly once and then removes the registration. It must not
  fire repeatedly for the same registration.
- Each registration is independent: a timeout (or heartbeat, or unregister) for one
  `name` must have no effect on any other `name`.
- A heartbeat that arrives after a registration has already timed out (and thus been
  removed) is treated as a heartbeat for an unknown name (no-op).

## Implementation notes

- Use `Process.send_after/3` (or `:timer`) to schedule timeouts, and guard against
  stale timers (e.g. by tagging each armed timer with a reference) so that a reset or
  unregister cannot let an old timer fire.
- Give me the complete module in a single file. Use only the OTP standard library,
  no external dependencies.