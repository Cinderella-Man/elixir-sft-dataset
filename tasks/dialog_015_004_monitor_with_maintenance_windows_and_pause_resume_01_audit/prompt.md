# Managed Monitor with Maintenance Windows and Pause/Resume

Implement an Elixir `GenServer` module called `ManagedMonitor` that supervises
registered services with periodic health checks, and adds operational controls on
top of plain up/down monitoring: individual services can be **paused** (checks
skipped) or put into a **maintenance window** (checks run, but failures are
forgiven) that expires automatically. Use only the OTP standard library — no
external dependencies — and deliver the complete module in a single file.

## Starting the monitor

`ManagedMonitor.start_link(opts \\ [])` starts and links the process and returns
the usual `GenServer.on_start()` result. `opts` is a keyword list:

- `:clock` — a zero-arity function returning the current time in milliseconds, used
  to timestamp checks and compute maintenance deadlines. Defaults to
  `fn -> System.monotonic_time(:millisecond) end`.
- `:notify` — a three-arity function `notify.(service_name, event, detail)` invoked
  on the events listed at the bottom. Defaults to no notifications.

Every public function below takes the server (pid) as its first argument.

## Registering services

`ManagedMonitor.register(server, service_name, check_func, interval_ms, max_failures \\ 3)`

- `service_name` is any term and identifies the service.
- `check_func` is a zero-arity function returning `:ok` (healthy) or
  `{:error, reason}` (unhealthy).
- `interval_ms` is the number of milliseconds between that service's checks.
- `max_failures` is the number of consecutive failures after which the service is
  marked `:down`. Defaults to `3`.

Returns `:ok` on success, or `{:error, :already_registered}` if a service with that
name is already registered — an existing registration is never replaced or altered
by a second `register` call.

On registration the service starts with health `:pending`, `consecutive_failures`
at `0`, and `last_check_at` at `nil`. Registration itself does not run a check; the
first check is scheduled `interval_ms` milliseconds later using
`Process.send_after`, and after each fired timer the next one is scheduled the same
way, so the timer keeps firing every `interval_ms` indefinitely (even while the
service is paused or in maintenance). The check-timer message MUST be exactly
`{:check, service_name}` — this message shape is part of the contract (see
"Triggering a check manually" below).

## Normal (active) checks

When the check timer fires for an active (not paused, not in-maintenance) service,
`check_func` is invoked inside the server process and the service is updated:

- `last_check_at` is set to the current `:clock` time.
- On `:ok`: the consecutive-failure counter resets to `0` and the health becomes
  `:up`.
- On `{:error, reason}`: the counter increments; the health is left unchanged while
  the counter is below `max_failures`.
- When the counter reaches `max_failures`, the health transitions to `:down` and
  `notify.(service_name, :down, reason)` fires exactly once, with the
  threshold-crossing check's reason. While already `:down` and still failing, no
  further `:down` notification fires.
- When a `:down` service's check returns `:ok`, it transitions back to `:up`,
  `notify.(service_name, :recovered, nil)` fires, the counter resets, and the
  `:down` notification is re-armed for any future run of failures.

## Pausing and resuming

- `ManagedMonitor.pause(server, service_name)` pauses monitoring. While paused, the
  check timers keep firing on schedule but `check_func` is NOT executed and nothing
  about the service changes; its reported `:status` is `:paused` while its health
  (`:pending`, `:up`, or `:down`) and failure counter are preserved unchanged
  underneath. Returns `:ok`, or `{:error, :not_found}` for an unknown service.
- `ManagedMonitor.resume(server, service_name)` resumes a service that is currently
  paused OR in maintenance; its reported status reverts to the preserved health,
  and the failure counter is preserved. Resuming a service that is neither paused
  nor in maintenance returns `{:error, :not_paused}`; an unknown service returns
  `{:error, :not_found}`. Resuming out of a maintenance window retires that
  window's pending expiry — it never fires afterwards (see the lifecycle rule
  below).

## Maintenance windows

`ManagedMonitor.maintenance(server, service_name, duration_ms)` puts a service into
maintenance mode for `duration_ms` milliseconds and returns `:ok` (or
`{:error, :not_found}`). `notify.(service_name, :maintenance_started, duration_ms)`
fires each time maintenance is entered (including re-entry).

During maintenance:

- The reported `:status` is `:maintenance`, and `:maintenance_ends_at` in the
  status map is the `:clock` time at which the window will expire
  (`clock_at_entry + duration_ms`).
- Check timers keep firing and `check_func` IS executed with `last_check_at`
  updated, but failures are forgiven: they do NOT increment the failure counter and
  can never cause a `:down` transition. Successes still reset the counter and set
  the underlying health to `:up`.

The window expires by itself: the expiry is tracked with a
`Process.send_after(self(), {:maintenance_end, service_name}, duration_ms)` timer.
On expiry, `notify.(service_name, :maintenance_ended, nil)` fires and the service
returns to normal monitoring, its reported status reverting to its current health.

### Replacing a maintenance window — lifecycle rule (important)

Calling `maintenance/3` while the service is already in maintenance REPLACES the
window: the duration restarts from now, `:maintenance_ends_at` reflects the new
deadline, and `:maintenance_started` fires again. The replaced window's expiry is
retired and must never act — in particular, EXTENDING a window (a short duration
replaced by a longer one) must keep the service in maintenance past the old
deadline, with no early exit and no spurious `:maintenance_ended`. The same
holds after a manual `resume/2`: a retired window's expiry never affects any
later maintenance session. A `{:maintenance_end, name}` message for a service
that is missing or no longer in maintenance is ignored.

## Triggering a check manually

Sending the server the message `{:check, service_name}` performs one check cycle
for that service immediately — with exactly the mode-dependent behavior above
(skipped while paused, forgiven while in maintenance, normal otherwise). Because a
`GenServer` processes its mailbox in order, sending `{:check, service_name}` and
then calling `ManagedMonitor.status/2` observes the state produced by that
completed cycle. A `{:check, name}` message for an unregistered name is ignored.
This documented message is how checks can be driven deterministically in tests.

## Querying

- `ManagedMonitor.status(server, service_name)` returns `{:ok, status_info}` for a
  registered service, or `{:error, :not_found}` otherwise. `status_info` is a map
  containing at least:
  - `:status` — `:pending`, `:up`, or `:down` for an active service; `:paused`
    while paused; `:maintenance` while in a maintenance window;
  - `:last_check_at` — the `:clock` time of the most recent executed check, or
    `nil` if none yet;
  - `:consecutive_failures` — the current run of uninterrupted counted failures;
  - `:maintenance_ends_at` — the current window's expiry time, or `nil` when not
    in maintenance.
- `ManagedMonitor.statuses(server)` returns a map of every registered service name
  to its `status_info` map.

## Deregistering — lifecycle rule (important)

`ManagedMonitor.deregister(server, service_name)` removes a service from
monitoring and always returns `:ok`, whether or not the service was registered
(and regardless of its mode). After `deregister` returns, the service no longer
appears in `statuses/1`, `status/2` returns `{:error, :not_found}`, and none of
the registration's scheduled messages may have any effect: a pending or future
`{:check, ...}` or `{:maintenance_end, ...}` for it must not run a check, must
not fire any notification, and must not resurrect any state. The same name may
be registered again afterwards, starting fresh in `:pending`, and the old
registration's leftover timers must not drive the new one.

## Notification events (summary)

- `notify.(name, :down, reason)` — health transition to `:down`, exactly once per
  down-transition.
- `notify.(name, :recovered, nil)` — health transition from `:down` to `:up`.
- `notify.(name, :maintenance_started, duration_ms)` — every entry (or re-entry)
  into maintenance.
- `notify.(name, :maintenance_ended, nil)` — a maintenance window expiring on its
  own (a manual `resume/2` does not fire it).

## Robustness

Unexpected messages sent to the server must be ignored — they must not crash the
process or alter any service's state.

Services are independent: one service's failures, pauses, or maintenance never
affect another service's health, counters, or windows.
