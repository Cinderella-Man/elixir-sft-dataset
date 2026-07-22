Write me an Elixir GenServer module called `CalendarScheduler` that accepts job registrations with **calendar-aware rules** (rather than cron expressions) and executes them at the right times.

The motivation: cron can't express rules like "first Monday of every month" or "last weekday of the month" without complex workarounds. This module uses a small set of higher-level tuple-based rules that directly encode these common calendar patterns. Unlike cron, the next-run calculation can't scan minute-by-minute — it has to use calendar math.

I need these functions in the public API:

- `CalendarScheduler.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning a `NaiveDateTime`. If not provided, default to `fn -> NaiveDateTime.utc_now() end`. It should also accept a `:name` option for process registration and a `:tick_interval_ms` option (default `1_000`) for the `Process.send_after(self(), :tick, ...)` period. Setting it to `:infinity` disables auto-ticking.

- `CalendarScheduler.register(server, name, rule, {mod, fun, args})` registers a job with a calendar rule. Returns `:ok`, `{:error, :invalid_rule}`, or `{:error, :already_exists}`. The supported rule shapes are exactly these four tuples:

  1. `{:nth_weekday_of_month, n, weekday, {hour, minute}}` — e.g. `{:nth_weekday_of_month, 1, :monday, {9, 0}}` = first Monday of each month at 09:00. `n` must be an integer in 1..4, `weekday` must be one of `:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday`, `hour` in 0..23, `minute` in 0..59.

  2. `{:last_weekday_of_month, weekday, {hour, minute}}` — e.g. `{:last_weekday_of_month, :friday, {17, 0}}` = last Friday of each month at 17:00.

  3. `{:nth_day_of_month, day, {hour, minute}}` — e.g. `{:nth_day_of_month, 15, {12, 0}}` = the 15th of each month at noon. `day` must be in 1..31. If a given month doesn't have that day (e.g. February 31), that month is **skipped** — the next_run will be the next month in which the day exists.

  4. `{:last_day_of_month, {hour, minute}}` — the last calendar day of each month. Correctly handles 28/29/30/31-day months.

- `CalendarScheduler.unregister(server, name)` — removes a job. Returns `:ok` or `{:error, :not_found}`.

- `CalendarScheduler.jobs(server)` — returns a list of `{name, rule, next_run}` tuples.

- `CalendarScheduler.next_run(server, name)` — returns `{:ok, next_run_datetime}` or `{:error, :not_found}`.

**The next-run algorithm** must be calendar-walking, not minute-scanning:

1. Start with `{year, month}` from the current clock time.
2. Compute the rule's target datetime within that month (if one exists — `:nth_day_of_month, 31` in February does not). This is a pure calendar computation:
   - For `:nth_weekday_of_month, n, weekday`: find the 1st of the month, compute days until the first matching weekday (use ISO day-of-week where Monday=1), then add `(n-1)*7`. If the resulting day number exceeds the month's length, the rule has no target in this month.
   - For `:last_weekday_of_month, weekday`: find the last day of the month, walk backwards until the weekday matches.
   - For `:nth_day_of_month, day`: valid if `day <= days_in_month(year, month)`.
   - For `:last_day_of_month`: always valid, uses `Calendar.ISO.days_in_month(year, month)`.
3. If the target datetime exists and is strictly greater than the given time, return it.
4. Otherwise advance to the next month (rolling year on December → January) and repeat from step 2.

Use `Calendar.ISO.days_in_month(year, month)` for month-length. Use `Date.day_of_week(date)` to get ISO weekday (Monday=1..Sunday=7). Weekday atoms map as: `:monday` → 1, `:tuesday` → 2, ..., `:sunday` → 7.

At registration, compute the initial `next_run` relative to the current clock.

On each `:tick`, read `now`, find all jobs whose `next_run <= now`, execute each one via `apply(mod, fun, args)` wrapped in try/rescue/catch so a crashing job doesn't kill the scheduler, and recompute `next_run` relative to `now`. Schedule the next tick if `tick_interval_ms != :infinity`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.