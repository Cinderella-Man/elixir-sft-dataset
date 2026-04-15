Write me an Elixir GenServer module called `Scheduler` that accepts job registrations with cron-like schedules and executes them at the right times.

I need these functions in the public API:

- `Scheduler.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning a `NaiveDateTime` representing the current time. If not provided, default to `fn -> NaiveDateTime.utc_now() end`. It should also accept a `:name` option for process registration and a `:tick_interval_ms` option (default `1_000`) that controls how frequently the GenServer checks for due jobs via `Process.send_after(self(), :tick, tick_interval_ms)`. Setting it to `:infinity` disables automatic ticking entirely (useful for testing).

- `Scheduler.register(server, name, cron_expression, {mod, fun, args})` which registers a named job. `name` is a string or atom identifier that must be unique. `cron_expression` is a string with exactly 5 space-separated fields: minute (0–59), hour (0–23), day-of-month (1–31), month (1–12), day-of-week (0–6, where 0 = Sunday). Return `:ok` on success. Return `{:error, :invalid_cron}` if the expression cannot be parsed or any value is out of range. Return `{:error, :already_exists}` if a job with that name is already registered. Upon successful registration, the GenServer must immediately calculate the job's next run time based on the current clock value.

- `Scheduler.unregister(server, name)` which removes a registered job. Return `:ok` if the job was found and removed. Return `{:error, :not_found}` if no job with that name exists.

- `Scheduler.jobs(server)` which returns a list of `{name, cron_expression, next_run}` tuples for all registered jobs, where `next_run` is a `NaiveDateTime`.

- `Scheduler.next_run(server, name)` which returns `{:ok, next_run_datetime}` for a registered job or `{:error, :not_found}` if the job doesn't exist.

The cron expression parser must support the following syntax in each of the 5 fields:
- `*` — matches every valid value for that field
- A specific integer (e.g. `5`)
- Comma-separated lists (e.g. `1,15,30`)
- Ranges with a dash (e.g. `1-5`)
- Step values with a slash (e.g. `*/5` or `10-30/5`)

When calculating the next run time from a given `NaiveDateTime`, the scheduler should find the earliest future datetime that matches all five cron fields simultaneously. It must advance at least one minute from the given time (truncating seconds to zero) and scan forward. Be careful with day-of-week: if the cron specifies a day-of-week, only datetimes falling on matching weekdays should be considered.

On each `:tick` message, the GenServer should read the current time from the clock function, find all jobs whose `next_run` is less than or equal to the current time, execute each one by calling `apply(mod, fun, args)`, and then recalculate their next run time from the current time. Multiple jobs that are due at the same tick must all execute. After processing, if `tick_interval_ms` is not `:infinity`, schedule the next tick with `Process.send_after`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.