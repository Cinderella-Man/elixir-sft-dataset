# Design Brief: Cron-Style Job `Scheduler`

## Problem

We need an Elixir GenServer module called `Scheduler` that accepts job registrations with cron-like schedules and executes them at the right times. Deliver the complete module in a single file.

## Constraints

- Use only the OTP standard library — no external dependencies.
- The cron expression parser must support the following syntax in each of the 5 fields:
  - `*` — matches every valid value for that field
  - A specific integer (e.g. `5`)
  - Comma-separated lists (e.g. `1,15,30`)
  - Ranges with a dash (e.g. `1-5`)
  - Step values with a slash (e.g. `*/5` or `10-30/5`). The step must be a positive integer; a step of `0` (as in `*/0`) is invalid. Stepping starts from the lower bound of the base range — the field's minimum for `*`, or the range's start otherwise — and selects every Nth matching value. For example, `*/15` in the minute field matches 0, 15, 30, 45; `10-30/10` matches 10, 20, 30; and `5-25/7` matches 5, 12, 19 (offsets 0, 7, 14 from the start value 5).
- A `cron_expression` is a string with exactly 5 space-separated fields: minute (0–59), hour (0–23), day-of-month (1–31), month (1–12), day-of-week (0–6, where 0 = Sunday).
- When calculating the next run time from a given `NaiveDateTime`, find the earliest future datetime that matches all five cron fields simultaneously. It must advance at least one minute from the given time (truncating seconds to zero) and scan forward. Be careful with day-of-week: if the cron specifies a day-of-week, only datetimes falling on matching weekdays should be considered.

## Required Interface

1. `Scheduler.start_link(opts)` — starts the process. It should accept a `:clock` option which is a zero-arity function returning a `NaiveDateTime` representing the current time. If not provided, default to `fn -> NaiveDateTime.utc_now() end`. It should also accept a `:name` option for process registration and a `:tick_interval_ms` option (default `1_000`) that controls how frequently the GenServer checks for due jobs via `Process.send_after(self(), :tick, tick_interval_ms)`. Setting it to `:infinity` disables automatic ticking entirely (useful for testing).

2. `Scheduler.register(server, name, cron_expression, {mod, fun, args})` — registers a named job. `name` is a string or atom identifier that must be unique. `cron_expression` is a string with exactly 5 space-separated fields as described above. Return `:ok` on success. Return `{:error, :invalid_cron}` if the expression cannot be parsed, any value is out of range, or the expression can never match any real datetime because no allowed day-of-month exists in any allowed month (e.g. `0 0 31 4 *` — April has 30 days — or a day of 30–31 in February; `0 0 29 2 *` is valid, since leap years have a February 29th). Return `{:error, :already_exists}` if a job with that name is already registered. Upon successful registration, the GenServer must immediately calculate the job's next run time based on the current clock value.

3. `Scheduler.unregister(server, name)` — removes a registered job. Return `:ok` if the job was found and removed. Return `{:error, :not_found}` if no job with that name exists.

4. `Scheduler.jobs(server)` — returns a list of `{name, cron_expression, next_run}` tuples for all registered jobs, where `next_run` is a `NaiveDateTime`.

5. `Scheduler.next_run(server, name)` — returns `{:ok, next_run_datetime}` for a registered job or `{:error, :not_found}` if the job doesn't exist.

## Acceptance Criteria

- On each `:tick` message, the GenServer reads the current time from the clock function, finds all jobs whose `next_run` is less than or equal to the current time, executes each one by calling `apply(mod, fun, args)`, and then recalculates their next run time from the current time.
- Multiple jobs that are due at the same tick must all execute.
- After processing, if `tick_interval_ms` is not `:infinity`, the next tick is scheduled with `Process.send_after`.
- The module is complete, in a single file, using only OTP standard library with no external dependencies.
