# Heartbeat Monitor

Implement an Elixir `GenServer` module called `Monitor` that supervises registered
services by running each service's health-check function on its own periodic
interval and tracking a per-service status. Use only the OTP standard library — no
external dependencies — and deliver the complete module in a single file.

## Starting the monitor

`Monitor.start_link(opts \\ [])` starts and links the process and returns the usual
`GenServer.on_start()` result. `opts` is a keyword list:

- `:clock` — a zero-arity function returning the current time in milliseconds, used
  to timestamp checks. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
- `:notify` — a two-arity function `notify.(service_name, reason)` invoked when a
  service transitions to `:down` (the exact rules are below). Defaults to no
  notification.

Every public function below takes the server (pid) as its first argument.

## Registering services

`Monitor.register(server, service_name, check_func, interval_ms, max_failures \\ 3)`

- `service_name` is any term and identifies the service.
- `check_func` is a zero-arity function that, when invoked, returns either `:ok`
  (healthy) or `{:error, reason}` (unhealthy), where `reason` is any term.
- `interval_ms` is the number of milliseconds between that service's checks.
- `max_failures` is the number of consecutive failures after which the service is
  marked `:down`. It defaults to `3`.

Returns `:ok` on success, or `{:error, :already_registered}` if a service with that
name is already registered — an existing registration is never replaced or altered
by a second `register` call.

On registration:

- The service starts in status `:pending`, with `consecutive_failures` at `0` and
  `last_check_at` set to `nil`.
- Registration itself does not run the check. The first check is scheduled to run
  `interval_ms` milliseconds later using `Process.send_after`, and after each
  completed check the next one is scheduled the same way, so checks repeat every
  `interval_ms` indefinitely. The timer message for a service MUST be exactly
  `{:check, service_name}` — this message shape is part of the contract (see
  "Triggering a check manually" below).

## Performing a check

Each check invokes the service's `check_func` inside the server process (call the
function directly) and then updates the service:

- `last_check_at` is set to the current `:clock` time for every completed check,
  successful or not.
- If the result is `:ok`: the consecutive-failure counter resets to `0` and the
  status becomes `:up`.
- If the result is `{:error, reason}`: the consecutive-failure counter increments
  by one. The status is left unchanged while the counter is below `max_failures`
  (a `:pending` service stays `:pending`, an `:up` service stays `:up`).
- When the counter reaches `max_failures`, the status transitions to `:down` and
  the `:notify` function is called exactly once as `notify.(service_name, reason)`,
  where `reason` comes from the latest (threshold-crossing) failing check.
- While a service is already `:down` and keeps failing, `notify` is NOT called
  again, and the counter keeps counting.
- If a `:down` service's check returns `:ok`, it transitions back to `:up`, the
  counter resets to `0`, and the notification is re-armed: a later run of
  `max_failures` consecutive failures transitions it to `:down` again and calls
  `notify` exactly once more, with the new failure's reason.

## Triggering a check manually

Sending the server the message `{:check, service_name}` performs one check for that
service immediately — exactly the same work a timer-driven check performs (invoking
the check function, updating `last_check_at`, the counter, the status, and firing
`notify` per the rules above). Because a `GenServer` processes its mailbox in order,
sending `{:check, service_name}` and then calling `Monitor.status/2` observes the
state produced by that completed check. A `{:check, name}` message for a name that
is not registered is ignored. This documented message is how checks can be driven
deterministically in tests.

## Querying

- `Monitor.status(server, service_name)` returns `{:ok, status_info}` for a
  registered service, or `{:error, :not_found}` otherwise. `status_info` is a map
  containing at least:
  - `:status` — one of `:pending`, `:up`, or `:down`;
  - `:last_check_at` — the `:clock` time of the most recent completed check, or
    `nil` if no check has completed yet;
  - `:consecutive_failures` — the current run of uninterrupted failures.
- `Monitor.statuses(server)` returns a map of every registered service name to its
  `status_info` map.

## Deregistering — lifecycle rule (important)

`Monitor.deregister(server, service_name)` removes a service from monitoring and
always returns `:ok`, whether or not the service was registered. Deregistering is
final for that registration's schedule:

- After `deregister` returns, the service no longer appears in `statuses/1` and
  `status/2` returns `{:error, :not_found}`.
- The registration's scheduled checks never run again: any pending or future timer
  message for that service must have no effect — it must not run the check
  function, must not fire `notify`, and must not resurrect any state.
- The same name may be registered again afterwards; the new registration starts
  fresh in `:pending`, and the OLD registration's leftover timers must not drive
  the new one (no early checks, no doubled cadence, no stale failure counting).

## Robustness

Unexpected messages sent to the server must be ignored — they must not crash the
process or alter any service's state.

Services are independent: one service failing (or going `:down`) never affects
another service's status or counters.
