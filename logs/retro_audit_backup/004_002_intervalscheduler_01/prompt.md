Write me an Elixir GenServer module called `IntervalScheduler` that accepts job registrations with simple interval schedules (every N seconds/minutes/hours/days) and executes them at drift-free intervals.

I need these functions in the public API:

- `IntervalScheduler.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning a `NaiveDateTime` representing the current time. If not provided, default to `fn -> NaiveDateTime.utc_now() end`. It should also accept a `:name` option for process registration and a `:tick_interval_ms` option (default `1_000`) that controls how frequently the GenServer checks for due jobs via `Process.send_after(self(), :tick, tick_interval_ms)`. Setting it to `:infinity` disables automatic ticking entirely (useful for testing).

- `IntervalScheduler.register(server, name, interval_spec, {mod, fun, args})` which registers a named job. `name` is a string or atom identifier that must be unique. `interval_spec` is a tuple of the form `{:every, n, unit}` where `n` is a positive integer and `unit` is one of `:seconds`, `:minutes`, `:hours`, `:days`. Return `:ok` on success. Return `{:error, :invalid_interval}` if the spec doesn't match this shape or the integer is non-positive. Return `{:error, :already_exists}` if a job with that name is already registered. Upon registration, record the current clock value as the job's `started_at` anchor and compute its initial `next_run`.

- `IntervalScheduler.unregister(server, name)` which removes a registered job. Return `:ok` if the job was found and removed. Return `{:error, :not_found}` if no job with that name exists.

- `IntervalScheduler.jobs(server)` which returns a list of `{name, interval_spec, next_run}` tuples for all registered jobs, where `next_run` is a `NaiveDateTime`.

- `IntervalScheduler.next_run(server, name)` which returns `{:ok, next_run_datetime}` for a registered job or `{:error, :not_found}` if the job doesn't exist.

The scheduling algorithm must be **drift-free**: the next_run for a job is always computed relative to the job's `started_at`, never relative to the actual execution time. Specifically, `next_run = started_at + N * interval_seconds` for the smallest integer N ≥ 1 such that the result is strictly greater than the current clock time. This has two important consequences:

- A tick that arrives slightly late does NOT push future scheduled times later. If started_at = T0, interval = 60s, and a tick arrives at T0 + 61s (one second late), the execution happens and the new next_run is T0 + 120s, not T0 + 121s. This prevents cumulative drift over long-running jobs.

- **Missed-interval catch-up is disabled.** If the scheduler was down (or the clock jumped forward) such that multiple interval boundaries were crossed without execution, each missed boundary is **skipped**, not replayed. If started_at = T0, interval = 60s, and a tick arrives at T0 + 250s, the job executes exactly once at T0 + 250s and its next_run is set to T0 + 300s (the next boundary > now) — NOT four separate catch-up executions for the missed boundaries at T0 + 60s, T0 + 120s, T0 + 180s, T0 + 240s.

On each `:tick` message, the GenServer should read the current time from the clock function, find all jobs whose `next_run` is less than or equal to the current time, execute each one by calling `apply(mod, fun, args)`, and then recalculate their next run time using the drift-free formula above. Multiple jobs that are due at the same tick must all execute. A job function that raises or throws must not crash the scheduler — wrap the `apply/3` call in a try/rescue/catch. After processing, if `tick_interval_ms` is not `:infinity`, schedule the next tick with `Process.send_after`.

Store the job data as a map or struct keyed by name, tracking at least the mfa tuple, the interval_spec, the `started_at` datetime, and the current `next_run` datetime.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.