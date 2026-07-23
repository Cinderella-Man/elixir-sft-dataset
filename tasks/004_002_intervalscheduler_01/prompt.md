# `IntervalScheduler` — GenServer for drift-free interval jobs

Implement an Elixir GenServer module `IntervalScheduler` that accepts job registrations with simple interval schedules (every N seconds/minutes/hours/days) and executes them at drift-free intervals. Single file, OTP standard library only, no external dependencies.

**Public API — `IntervalScheduler.start_link(opts)`**
- Starts the process.
- Accepts `:clock` — a zero-arity function returning a `NaiveDateTime` for the current time. Default: `fn -> NaiveDateTime.utc_now() end`.
- Accepts `:name` for process registration.
- Accepts `:tick_interval_ms` (default `1_000`) controlling how frequently the GenServer checks for due jobs via `Process.send_after(self(), :tick, tick_interval_ms)`.
- `:infinity` for `:tick_interval_ms` disables automatic ticking entirely (useful for testing).

**Public API — `IntervalScheduler.register(server, name, interval_spec, {mod, fun, args})`**
- Registers a named job. `name` is a string or atom identifier that must be unique.
- `interval_spec` is a tuple `{:every, n, unit}` where `n` is a positive integer and `unit` is one of `:seconds`, `:minutes`, `:hours`, `:days`.
- Return `:ok` on success.
- Return `{:error, :invalid_interval}` if the spec doesn't match this shape or the integer is non-positive.
- Return `{:error, :already_exists}` if a job with that name is already registered.
- On registration, record the current clock value as the job's `started_at` anchor and compute its initial `next_run`.

**Public API — `IntervalScheduler.unregister(server, name)`**
- Removes a registered job.
- Return `:ok` if the job was found and removed.
- Return `{:error, :not_found}` if no job with that name exists.

**Public API — `IntervalScheduler.jobs(server)`**
- Returns a list of `{name, interval_spec, next_run}` tuples for all registered jobs, where `next_run` is a `NaiveDateTime`.

**Public API — `IntervalScheduler.next_run(server, name)`**
- Returns `{:ok, next_run_datetime}` for a registered job.
- Returns `{:error, :not_found}` if the job doesn't exist.

**Scheduling algorithm — drift-free**
- `next_run` for a job is always computed relative to the job's `started_at`, never relative to the actual execution time.
- Formula: `next_run = started_at + N * interval_seconds` for the smallest integer N ≥ 1 such that the result is strictly greater than the current clock time.

**Consequence — late ticks do not push schedules later**
- A tick that arrives slightly late does NOT push future scheduled times later.
- If started_at = T0, interval = 60s, and a tick arrives at T0 + 61s (one second late), the execution happens and the new next_run is T0 + 120s, not T0 + 121s. This prevents cumulative drift over long-running jobs.

**Consequence — missed-interval catch-up is disabled**
- If the scheduler was down (or the clock jumped forward) such that multiple interval boundaries were crossed without execution, each missed boundary is skipped, not replayed.
- If started_at = T0, interval = 60s, and a tick arrives at T0 + 250s, the job executes exactly once at T0 + 250s and its next_run is set to T0 + 300s (the next boundary > now) — NOT four separate catch-up executions for the missed boundaries at T0 + 60s, T0 + 120s, T0 + 180s, T0 + 240s.

**`:tick` handling**
- Read the current time from the clock function.
- Find all jobs whose `next_run` is less than or equal to the current time.
- Execute each by calling `apply(mod, fun, args)`, then recalculate its next run time using the drift-free formula above.
- Multiple jobs due at the same tick must all execute.
- A job function that raises or throws must not crash the scheduler — wrap the `apply/3` call in a try/rescue/catch.
- After processing, if `tick_interval_ms` is not `:infinity`, schedule the next tick with `Process.send_after`.

**State**
- Store job data as a map or struct keyed by name, tracking at least the mfa tuple, the interval_spec, the `started_at` datetime, and the current `next_run` datetime.

**Deliverable**
- The complete module in a single file. Use only OTP standard library, no external dependencies.
