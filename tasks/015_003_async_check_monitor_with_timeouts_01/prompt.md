Write me an Elixir GenServer module called `AsyncMonitor` that monitors registered services via periodic health checks where each check runs asynchronously in a spawned Task with a configurable timeout.

I need these functions in the public API:

- `AsyncMonitor.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration and a `:notify` option which is a function of the form `fn service_name, reason -> ... end` that gets called when a service transitions to `:down`.

- `AsyncMonitor.register(server, service_name, check_func, interval_ms, opts \\ [])` which registers a service to be monitored. `check_func` is a zero-arity function that returns `:ok` or `{:error, reason}`. `interval_ms` is how often to run the check. `opts` accepts `:max_failures` (consecutive failures before `:down`, default 3) and `:timeout_ms` (maximum time a check is allowed to run, default 5000). Return `:ok` if registered successfully, or `{:error, :already_registered}` if a service with that name is already registered.

- `AsyncMonitor.status(server, service_name)` which returns the current status of a single service as `{:ok, status_info}` where `status_info` is a map containing at least `:status` (one of `:up`, `:down`, or `:pending`), `:last_check_at` (timestamp or `nil`), `:consecutive_failures` (integer), and `:check_in_flight` (boolean indicating whether a check Task is currently running). Return `{:error, :not_found}` if the service isn't registered.

- `AsyncMonitor.statuses(server)` which returns a map of all registered service names to their `status_info` maps.

- `AsyncMonitor.deregister(server, service_name)` which removes a service from monitoring, cancels any pending scheduled check, and shuts down any in-flight check Task for that service. Return `:ok` regardless of whether the service existed.

Each service should start in `:pending` status immediately after registration. The first check should be scheduled to run after `interval_ms` milliseconds using `Process.send_after` with a tagged message like `{:schedule_check, service_name}`. When this message fires, the GenServer spawns a `Task` to execute the check function. The GenServer monitors the Task and stores its reference. The Task sends `{:check_result, service_name, task_ref, result}` back to the GenServer when done.

If the Task does not complete within `timeout_ms`, the GenServer receives a `{:check_timeout, service_name, task_ref}` message (scheduled via a separate `Process.send_after` at spawn time) and kills the Task with `Process.exit(task_pid, :kill)`. A timeout is treated as a failure with reason `:timeout`.

After processing a check result (success, failure, or timeout), the next check is scheduled `interval_ms` later. If a check Task's reference doesn't match the currently expected reference for that service (because the service was deregistered and re-registered, or the timeout already fired), the result is silently discarded.

When a check function returns `{:error, reason}` or times out, the consecutive failure counter increments. When it returns `:ok`, the counter resets to zero and the status becomes `:up`. When the consecutive failure count reaches `max_failures`, the status transitions to `:down` and the notification function is called exactly once with `(service_name, reason)`. If the service is already `:down` and keeps failing, do not call the notification function again. If a `:down` service later returns `:ok`, it transitions back to `:up`, resets the failure counter, and a subsequent failure-to-down transition should trigger the notification again.

Only one check Task should be in flight per service at any time. Make sure deregistering a service prevents any pending schedule message or in-flight Task result from having an effect.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.