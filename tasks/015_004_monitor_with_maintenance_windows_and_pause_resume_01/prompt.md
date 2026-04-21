Write me an Elixir GenServer module called `ManagedMonitor` that monitors registered services via periodic heartbeat checks with support for maintenance windows and manual pause/resume of individual services.

I need these functions in the public API:

- `ManagedMonitor.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration and a `:notify` option which is a function of the form `fn service_name, event, detail -> ... end` that gets called on status transitions (see below).

- `ManagedMonitor.register(server, service_name, check_func, interval_ms, max_failures \\ 3)` which registers a service to be monitored. `check_func` is a zero-arity function that returns `:ok` or `{:error, reason}`. `interval_ms` is how often to run the check. `max_failures` is how many consecutive failures before the service is marked `:down`. Return `:ok` if registered successfully, or `{:error, :already_registered}` if a service with that name is already registered.

- `ManagedMonitor.status(server, service_name)` which returns the current status of a single service as `{:ok, status_info}` where `status_info` is a map containing at least `:status` (one of `:up`, `:down`, `:pending`, `:paused`, or `:maintenance`), `:last_check_at` (timestamp or `nil`), `:consecutive_failures` (integer), and `:maintenance_ends_at` (timestamp or `nil`). Return `{:error, :not_found}` if the service isn't registered.

- `ManagedMonitor.statuses(server)` which returns a map of all registered service names to their `status_info` maps.

- `ManagedMonitor.deregister(server, service_name)` which removes a service from monitoring and cancels its scheduled checks. Return `:ok` regardless of whether the service existed.

- `ManagedMonitor.pause(server, service_name)` which pauses monitoring of a service. While paused, scheduled check timers continue to fire but the check function is NOT executed — the service stays in its pre-pause health state internally but its reported status becomes `:paused`. Return `:ok` or `{:error, :not_found}`.

- `ManagedMonitor.resume(server, service_name)` which resumes a paused service. The reported status reverts to whatever the health state was before pausing (`:pending`, `:up`, or `:down`). The consecutive failure counter is preserved. Return `:ok`, `{:error, :not_found}`, or `{:error, :not_paused}` if the service isn't currently paused or in maintenance.

- `ManagedMonitor.maintenance(server, service_name, duration_ms)` which puts a service into maintenance mode for `duration_ms` milliseconds. During maintenance, check timers fire and the check function IS executed, but failures do NOT increment the consecutive failure counter and do NOT trigger `:down` transitions. Successes still reset the failure counter and update the health state to `:up`. The reported status is `:maintenance`. When the duration expires (tracked via `Process.send_after` with a `{:maintenance_end, service_name}` message), the service automatically resumes normal monitoring — its reported status reverts to its current health state. Return `:ok` or `{:error, :not_found}`. If already in maintenance, the duration is replaced (restarted).

The notification function `notify(service_name, event, detail)` should be called for these events:
- `(:down, reason)` — when a service transitions to `:down` (same semantics as before: exactly once per down-transition, not while already `:down`, re-arms on recovery).
- `(:recovered, nil)` — when a service transitions from `:down` to `:up`.
- `(:maintenance_started, duration_ms)` — when maintenance mode begins.
- `(:maintenance_ended, nil)` — when maintenance mode expires.

Checks should be executed inside the GenServer process (just call the function directly). Use tagged `Process.send_after` messages for scheduling, e.g. `{:check, service_name}`. Make sure deregistering a service prevents any pending check or maintenance-end message from having an effect. When a paused service is deregistered, no special handling is needed beyond removing it. When a maintenance service is deregistered, the pending maintenance-end timer is effectively orphaned and discarded when it fires for a missing service.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.