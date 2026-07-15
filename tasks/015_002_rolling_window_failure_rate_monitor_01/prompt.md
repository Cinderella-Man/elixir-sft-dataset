# Rolling-Window Failure-Rate Monitor

Implement an Elixir `GenServer` module called `RateMonitor` that supervises
registered services by running each service's health-check function on its own
periodic interval. Unlike a consecutive-failure monitor, service health is judged by
the **failure rate over a rolling window** of the most recent checks. Use only the
OTP standard library — no external dependencies — and deliver the complete module in
a single file.

## Starting the monitor

`RateMonitor.start_link(opts \\ [])` starts and links the process and returns the
usual `GenServer.on_start()` result. `opts` is a keyword list:

- `:clock` — a zero-arity function returning the current time in milliseconds, used
  to timestamp checks. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
- `:notify` — a two-arity function `notify.(service_name, failure_rate)` invoked
  when a service transitions to `:down` (rules below). Defaults to no notification.

Every public function below takes the server (pid) as its first argument.

## Registering services

`RateMonitor.register(server, service_name, check_func, interval_ms, opts \\ [])`

- `service_name` is any term and identifies the service.
- `check_func` is a zero-arity function returning `:ok` (healthy) or
  `{:error, reason}` (unhealthy).
- `interval_ms` is the number of milliseconds between that service's checks.
- `opts` is a keyword list:
  - `:window_size` — how many recent checks the rolling window holds. Defaults
    to `5`.
  - `:threshold` — the failure rate (a float in `0.0..1.0`) at or above which the
    service is marked `:down`. Defaults to `0.6`.

Returns `:ok` on success, or `{:error, :already_registered}` if a service with that
name is already registered — an existing registration is never replaced or altered
by a second `register` call.

On registration:

- The service starts in status `:pending` with an empty check history
  (`checks_in_window` is `0`, `failure_rate` is `0.0`, `last_check_at` is `nil`).
- Registration itself does not run the check. The first check is scheduled to run
  `interval_ms` milliseconds later using `Process.send_after`, and after each
  completed check the next one is scheduled the same way, so checks repeat every
  `interval_ms` indefinitely. The timer message for a service MUST be exactly
  `{:check, service_name}` — this message shape is part of the contract (see
  "Triggering a check manually" below).

## Performing a check

Each check invokes the service's `check_func` inside the server process and then
updates the service:

- `last_check_at` is set to the current `:clock` time for every completed check.
- The check's outcome (`:ok` or error) is appended to the service's history, which
  is bounded: only the most recent `window_size` outcomes are kept, so the oldest
  entry is evicted once the window is full, and `checks_in_window` never exceeds
  `window_size`.
- The failure rate is recomputed as `number_of_errors / length(history)` over the
  current window (it is `0.0` while the history is empty).
- The status is then re-evaluated:
  - **Full window** (`window_size` outcomes recorded): the service is `:down` when
    the failure rate is **greater than or equal to** the threshold — an
    exact-threshold rate counts as a breach — and `:up` otherwise.
  - **Partial window** (fewer than `window_size` outcomes): the service can never
    be `:down`. With zero errors recorded so far it is `:up`. With at least one
    error in the partial window: a `:pending` service becomes `:up` only when this
    check succeeded (otherwise it stays `:pending`), and a service that is already
    `:up` stays `:up`.
- Recovery is rate-driven, not event-driven: a `:down` service becomes `:up` only
  when enough new outcomes shift the full window's failure rate below the
  threshold — a single success is not sufficient while the window is still
  dominated by failures.

Notifications:

- When a service transitions to `:down` (it was not `:down` before), the `:notify`
  function is called exactly once as `notify.(service_name, failure_rate)`, with
  the failure rate that caused the transition.
- While a service is already `:down` and stays `:down`, `notify` is NOT called
  again.
- After a recovery to `:up`, the notification is re-armed: a later breach that
  transitions the service to `:down` again calls `notify` exactly once more.

## Triggering a check manually

Sending the server the message `{:check, service_name}` performs one check for that
service immediately — exactly the same work a timer-driven check performs. Because a
`GenServer` processes its mailbox in order, sending `{:check, service_name}` and
then calling `RateMonitor.status/2` observes the state produced by that completed
check. A `{:check, name}` message for a name that is not registered is ignored. This
documented message is how checks can be driven deterministically in tests.

## Querying

- `RateMonitor.status(server, service_name)` returns `{:ok, status_info}` for a
  registered service, or `{:error, :not_found}` otherwise. `status_info` is a map
  containing at least:
  - `:status` — one of `:pending`, `:up`, or `:down`;
  - `:last_check_at` — the `:clock` time of the most recent completed check, or
    `nil` if none yet;
  - `:failure_rate` — the current window's failure rate (a float in `0.0..1.0`,
    `0.0` with no checks yet);
  - `:checks_in_window` — how many outcomes the window currently holds (an
    integer, at most `window_size`).
- `RateMonitor.statuses(server)` returns a map of every registered service name to
  its `status_info` map.

## Deregistering — lifecycle rule (important)

`RateMonitor.deregister(server, service_name)` removes a service from monitoring
and always returns `:ok`, whether or not the service was registered. Deregistering
is final for that registration's schedule:

- After `deregister` returns, the service no longer appears in `statuses/1` and
  `status/2` returns `{:error, :not_found}`.
- The registration's scheduled checks never run again: any pending or future timer
  message for that service must have no effect — it must not run the check
  function, must not fire `notify`, and must not resurrect any state.
- The same name may be registered again afterwards; the new registration starts
  fresh in `:pending` with an empty window, and the OLD registration's leftover
  timers must not drive the new one.

## Robustness

Unexpected messages sent to the server must be ignored — they must not crash the
process or alter any service's state.

Services are independent: one service's failures never affect another service's
window, rate, or status.
