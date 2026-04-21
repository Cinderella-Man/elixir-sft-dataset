Write me an Elixir GenServer module called `RateMonitor` that monitors registered services using a rolling-window failure rate instead of consecutive failure counts.

I need these functions in the public API:

- `RateMonitor.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration and a `:notify` option which is a function of the form `fn service_name, failure_rate -> ... end` that gets called when a service transitions to `:down`.

- `RateMonitor.register(server, service_name, check_func, interval_ms, opts \\ [])` which registers a service to be monitored. `check_func` is a zero-arity function that returns `:ok` or `{:error, reason}`. `interval_ms` is how often to run the check. `opts` accepts `:window_size` (number of recent checks to consider, default 5) and `:threshold` (failure rate as a float 0.0–1.0 at which the service is marked `:down`, default 0.6). Return `:ok` if registered successfully, or `{:error, :already_registered}` if a service with that name is already registered.

- `RateMonitor.status(server, service_name)` which returns the current status of a single service as `{:ok, status_info}` where `status_info` is a map containing at least `:status` (one of `:up`, `:down`, or `:pending`), `:last_check_at` (timestamp or `nil`), `:failure_rate` (float 0.0–1.0 computed from the window, or `0.0` if no checks yet), and `:checks_in_window` (integer count of checks recorded so far, up to `:window_size`). Return `{:error, :not_found}` if the service isn't registered.

- `RateMonitor.statuses(server)` which returns a map of all registered service names to their `status_info` maps.

- `RateMonitor.deregister(server, service_name)` which removes a service from monitoring and cancels its scheduled checks. Return `:ok` regardless of whether the service existed.

Each service should start in `:pending` status immediately after registration with an empty check history. The first check should be scheduled to run after `interval_ms` milliseconds using `Process.send_after`. After each check, the next one is scheduled the same way. The check result (`:ok` or `:error`) is appended to a bounded list of the last `window_size` results. The failure rate is computed as `number_of_errors / length(history)`. If the failure rate is `>= threshold` AND the history contains at least `window_size` entries, the status becomes `:down`. If the failure rate drops below the threshold, the status becomes `:up`. While fewer than `window_size` checks have been recorded, the service cannot transition to `:down` — it stays `:pending` or `:up`.

When a service transitions to `:down` (was not `:down` before), the notification function is called exactly once with `(service_name, failure_rate)`. If the service is already `:down` and stays `:down`, do not call the notification function again. If a `:down` service's failure rate drops below the threshold, it transitions back to `:up`, and a subsequent failure-rate breach should trigger the notification again.

Checks should be executed inside the GenServer process (just call the function directly). Use tagged `Process.send_after` messages so that each service's timer can be identified, for example `{:check, service_name}`. Make sure deregistering a service prevents any pending check message for that service from having an effect.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.