# Async Check Monitor with Timeouts

Implement an Elixir `GenServer` module called `AsyncMonitor` that supervises
registered services by running each service's health check **asynchronously in a
spawned Task** with a per-service timeout, so a slow or hung check can never block
the monitor or other services. Use only the OTP standard library — no external
dependencies — and deliver the complete module in a single file.

## Starting the monitor

`AsyncMonitor.start_link(opts \\ [])` starts and links the process and returns the
usual `GenServer.on_start()` result. `opts` is a keyword list:

- `:clock` — a zero-arity function returning the current time in milliseconds, used
  to timestamp checks. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
- `:notify` — a two-arity function `notify.(service_name, reason)` invoked when a
  service transitions to `:down` (rules below). Defaults to no notification.

Every public function below takes the server (pid) as its first argument.

## Registering services

`AsyncMonitor.register(server, service_name, check_func, interval_ms, opts \\ [])`

- `service_name` is any term and identifies the service.
- `check_func` is a zero-arity function returning `:ok` (healthy) or
  `{:error, reason}` (unhealthy).
- `interval_ms` is the number of milliseconds between that service's checks.
- `opts` is a keyword list:
  - `:max_failures` — consecutive failures (including timeouts) before the service
    is marked `:down`. Defaults to `3`.
  - `:timeout_ms` — the maximum time a single check Task may run. Defaults to
    `5000`.

Returns `:ok` on success, or `{:error, :already_registered}` if a service with that
name is already registered — an existing registration is never replaced or altered
by a second `register` call.

On registration the service starts in status `:pending`, with `consecutive_failures`
at `0`, `last_check_at` at `nil`, and no check in flight. Registration itself does
not run a check; the first check is scheduled `interval_ms` milliseconds later.

## The check protocol (part of the contract)

The message shapes below are the documented protocol — tests drive and observe the
monitor through them, so implement them exactly:

- Scheduling: each service's next check is armed with
  `Process.send_after(self(), {:schedule_check, service_name}, interval_ms)`.
  Receiving `{:schedule_check, service_name}` starts one check for that service:
  the GenServer spawns a `Task` executing `check_func`, monitors it, and stores the
  Task's reference as the service's currently expected reference
  (`check_in_flight` becomes `true`).
- Completion: the Task sends `{:check_result, service_name, task_ref, result}`
  back to the GenServer when the check function returns.
- Timeout: at spawn time the GenServer also arms
  `Process.send_after(self(), {:check_timeout, service_name, task_ref}, timeout_ms)`.
  If the timeout message arrives while that same Task is still the expected
  in-flight check, the GenServer kills the Task with `Process.exit(task_pid, :kill)`
  and treats the check as a failure with reason `:timeout`.
- Staleness: a `{:check_result, ...}` or `{:check_timeout, ...}` whose `task_ref`
  does not match the service's currently expected reference — because the timeout
  already fired, the result already arrived, or the service was deregistered or
  re-registered in between — is silently discarded and changes nothing.
- After a check concludes (success, failure, or timeout), `check_in_flight` returns
  to `false` and the next check is scheduled `interval_ms` later.
- Only one check Task is ever in flight per service; `{:schedule_check, name}` for
  an unregistered name is ignored.

Because a `GenServer` processes its mailbox in order, sending the server
`{:schedule_check, service_name}` and then making a synchronous call (such as
`status/2`) is the documented deterministic way to drive a check in tests.

## Check outcomes

- `last_check_at` is set to the current `:clock` time when a check concludes.
- On `:ok`: the consecutive-failure counter resets to `0` and the status becomes
  `:up`.
- On `{:error, reason}` or a timeout (reason `:timeout`): the counter increments;
  the status is left unchanged while the counter is below `max_failures`.
- When the counter reaches `max_failures`, the status transitions to `:down` and
  `notify.(service_name, reason)` is called exactly once, with the reason from the
  latest (threshold-crossing) failure.
- While already `:down` and still failing, `notify` is NOT called again.
- If a `:down` service's check returns `:ok`, it transitions back to `:up`, the
  counter resets, and the notification is re-armed: a later run to `max_failures`
  calls `notify` exactly once more, with the new failure's reason.

## Querying

- `AsyncMonitor.status(server, service_name)` returns `{:ok, status_info}` for a
  registered service, or `{:error, :not_found}` otherwise. `status_info` is a map
  containing at least:
  - `:status` — one of `:pending`, `:up`, or `:down`;
  - `:last_check_at` — the `:clock` time of the most recent concluded check, or
    `nil` if none yet;
  - `:consecutive_failures` — the current run of uninterrupted failures;
  - `:check_in_flight` — a boolean, `true` while a check Task is currently
    running for the service.
- `AsyncMonitor.statuses(server)` returns a map of every registered service name
  to its `status_info` map.

## Deregistering — lifecycle rule (important)

`AsyncMonitor.deregister(server, service_name)` removes a service from monitoring
and always returns `:ok`, whether or not the service was registered. Deregistering
is final for that registration:

- After `deregister` returns, the service no longer appears in `statuses/1` and
  `status/2` returns `{:error, :not_found}`.
- Any in-flight check Task for the service is shut down, and the registration's
  scheduled messages never have an effect again: a pending or future
  `{:schedule_check, ...}`, `{:check_result, ...}`, or `{:check_timeout, ...}`
  belonging to it must not run a check, must not fire `notify`, and must not
  resurrect any state.
- The same name may be registered again afterwards; the new registration starts
  fresh in `:pending`, and the OLD registration's leftover messages must not drive
  the new one (the reference match above guarantees this).

## Robustness

Unexpected messages sent to the server must be ignored — they must not crash the
process or alter any service's state.

Services are independent: concurrent checks for different services run in separate
Tasks, and one service's failures, timeouts, or `:down` status never affect
another's counters or status. The GenServer itself must remain responsive while
check Tasks execute.
