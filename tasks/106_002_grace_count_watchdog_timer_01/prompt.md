# Grace-Count Watchdog Timer GenServer

Write me an Elixir GenServer module called `GraceWatchdog` that monitors the liveness
of registered processes using a heartbeat mechanism, but which tolerates a configurable
number of *consecutive missed intervals* before it declares an entity dead. Unlike a
plain watchdog that fires on the first missed heartbeat, this one only invokes the
timeout callback after the entity has missed its check-in `max_misses` times in a row.

## Public API

- `GraceWatchdog.start_link(opts)` — starts the process.
  - Accepts a `:name` option for process registration. If not provided, the server
    registers itself under the name `GraceWatchdog` (i.e. `__MODULE__`), because all
    other API functions target that fixed registered name and take no server argument.
  - Returns `{:ok, pid}` (standard `GenServer.start_link/3` return).

- `GraceWatchdog.register(name, pid, interval_ms, max_misses, on_timeout_fn)` — begins
  monitoring an entity identified by `name` (any term).
  - `pid` is the process associated with this registration; record it, but the watchdog
    is **not** required to monitor the pid for `:DOWN`/exit events — liveness is
    determined purely by heartbeats.
  - `interval_ms` is the maximum time (in milliseconds) allowed between heartbeats
    before a *miss* is recorded.
  - `max_misses` is a positive integer: the number of consecutive missed intervals that
    must elapse before the timeout callback fires.
  - `on_timeout_fn` is a **two-argument** function. When the miss threshold is reached
    the watchdog invokes it as `on_timeout_fn.(name, miss_count)` where `miss_count`
    equals `max_misses`.
  - The clock starts immediately: the first miss is recorded `interval_ms` after
    registration if no heartbeat has arrived.
  - Each elapsed interval with no heartbeat increments the miss counter and re-arms a
    fresh timer for another `interval_ms`. Only when the counter reaches `max_misses`
    is the callback invoked and the registration removed.
  - Registering a `name` that is already registered **replaces** the previous
    registration entirely (new pid, interval, threshold, callback, a reset miss count,
    and a freshly armed timer).
  - Returns `:ok`. This call must be synchronous — once it returns, the timer is armed.

- `GraceWatchdog.heartbeat(name)` — records a heartbeat for `name`, resetting its miss
  counter to `0` and re-arming its timer so the entity has another full `interval_ms`
  before the next miss.
  - Calling `heartbeat/1` for an unregistered `name` is a harmless no-op.
  - Returns `:ok`, synchronously.

- `GraceWatchdog.misses(name)` — returns `{:ok, current_miss_count}` for a registered
  `name`, or `{:error, :not_registered}` otherwise.

- `GraceWatchdog.unregister(name)` — stops monitoring `name`. After this returns, no
  timeout callback may fire for that `name`. Unregistering an unknown `name` is a no-op.
  Returns `:ok`.

## Timeout semantics

- The timeout is **one-shot**: once the miss threshold is reached, the watchdog invokes
  `on_timeout_fn.(name, max_misses)` exactly once and removes the registration.
- A single heartbeat resets the miss count to zero — a burst of misses that stops short
  of the threshold and is then interrupted by a heartbeat must never fire.
- Each registration is independent: misses, heartbeats, and unregisters for one `name`
  must have no effect on any other `name`.

## Implementation notes

- Use `Process.send_after/3` (or `:timer`) to schedule ticks, and guard against stale
  timers (e.g. by tagging each armed timer with a reference) so a reset or unregister
  cannot let an old timer increment the counter or fire.
- Give me the complete module in a single file. Use only the OTP standard library,
  no external dependencies.