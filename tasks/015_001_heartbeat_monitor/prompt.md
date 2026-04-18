Write me an Elixir GenServer module called `Monitor` that monitors registered services via periodic heartbeat checks.

I need these functions in the public API:

- `Monitor.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration and a `:notify` option which is a function of the form `fn service_name, reason -> ... end` that gets called when a service transitions to `:down`.

- `Monitor.register(server, service_name, check_func, interval_ms, max_failures \\ 3)` which registers a service to be monitored. `check_func` is a zero-arity function that returns `:ok` or `{:error, reason}`. `interval_ms` is how often to run the check. `max_failures` is how many consecutive failures before the service is marked `:down`. Return `:ok` if registered successfully, or `{:error, :already_registered}` if a service with that name is already registered.

- `Monitor.status(server, service_name)` which returns the current status of a single service as `{:ok, status_info}` where `status_info` is a map containing at least `:status` (one of `:up`, `:down`, or `:pending`), `:last_check_at` (timestamp or `nil`), and `:consecutive_failures` (integer). Return `{:error, :not_found}` if the service isn't registered.

- `Monitor.statuses(server)` which returns a map of all registered service names to their `status_info` maps.

- `Monitor.deregister(server, service_name)` which removes a service from monitoring and cancels its scheduled checks. Return `:ok` regardless of whether the service existed.

Each service should start in `:pending` status immediately after registration. The first check should be scheduled to run after `interval_ms` milliseconds using `Process.send_after`. After each check, the next one is scheduled the same way. When a check function returns `{:error, reason}` the consecutive failure counter increments. When it returns `:ok`, the counter resets to zero and the status becomes `:up`. When the consecutive failure count reaches `max_failures`, the status transitions to `:down` and the notification function is called exactly once with `(service_name, reason)` where `reason` is from the latest failure. If the service is already `:down` and keeps failing, do not call the notification function again. If a `:down` service later returns `:ok`, it transitions back to `:up`, resets the failure counter, and a subsequent failure-to-down transition should trigger the notification again.

Checks should be executed inside the GenServer process (just call the function directly). Use tagged `Process.send_after` messages so that each service's timer can be identified, for example `{:check, service_name}`. Make sure deregistering a service prevents any pending check message for that service from having an effect.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.