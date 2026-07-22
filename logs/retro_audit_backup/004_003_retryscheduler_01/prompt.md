Write me an Elixir GenServer module called `RetryScheduler` that executes **one-shot** jobs at a specified future time, retrying with exponential backoff if the job fails.

The motivation: unlike a recurring scheduler, a retry scheduler runs each job a bounded number of times — once on the scheduled time, then up to N-1 retries on failure, with each retry delayed by an increasing backoff. Once the job either succeeds or exhausts its retry budget, it enters a terminal state and is kept in the registry for inspection but never re-executed.

I need these functions in the public API:

- `RetryScheduler.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning a `NaiveDateTime`. If not provided, default to `fn -> NaiveDateTime.utc_now() end`. It should also accept a `:name` option for process registration and a `:tick_interval_ms` option (default `1_000`) for the `Process.send_after(self(), :tick, ...)` period. Setting it to `:infinity` disables auto-ticking (useful for testing).

- `RetryScheduler.schedule(server, name, run_at, {mod, fun, args}, opts \\ [])` where:
  - `name` is a unique string or atom identifier for the job
  - `run_at` is a `NaiveDateTime` specifying when the first attempt should happen
  - The mfa tuple is what gets invoked
  - `opts` may contain `:max_attempts` (default 3), `:base_delay_ms` (default 1_000), and `:backoff_factor` (default 2.0, must be >= 1.0)

  Returns `:ok` on success, `{:error, :already_exists}` if the name is taken, or `{:error, :invalid_opts}` if any option is out of range. A job scheduled with run_at in the past is still valid — it will fire on the next tick whose clock time is >= run_at.

- `RetryScheduler.cancel(server, name)` — removes a job from the registry if it exists. Returns `:ok` or `{:error, :not_found}`. Cancellation is valid in any state, including terminal states (:completed, :dead); the job is simply removed.

- `RetryScheduler.status(server, name)` — returns `{:ok, status, attempts_so_far}` where `status` is one of `:pending` (not yet attempted, or currently waiting for a retry), `:completed` (successful attempt), or `:dead` (exhausted retry budget). Returns `{:error, :not_found}` if no such job.

- `RetryScheduler.jobs(server)` — returns a list of `{name, status, next_attempt_at, attempts_so_far}` tuples for all jobs. Jobs in `:completed` or `:dead` state still have a `next_attempt_at` value, which refers to the attempt that ultimately succeeded or failed.

On each `:tick` message, the scheduler should:
1. Read `now` from the clock.
2. Find all jobs where `status == :pending` AND `next_attempt_at <= now`. Jobs in `:completed` or `:dead` are never re-picked.
3. For each due job, execute `apply(mod, fun, args)` inside a try/rescue/catch and classify the outcome:
   - Return value is `:ok` or matches `{:ok, _}` → **success**
   - Return value is `:error` or matches `{:error, _}` → **failure**
   - Function raises an exception → **failure**
   - Function throws → **failure**
   - Any other return value → **failure**
4. Update the job's state:
   - Always increment `attempts_so_far` by 1.
   - On success: set `status = :completed`.
   - On failure, if `attempts_so_far >= max_attempts`: set `status = :dead`.
   - On failure, if `attempts_so_far < max_attempts`: keep `status = :pending`, set `next_attempt_at = now + delay_ms` where `delay_ms = round(base_delay_ms * backoff_factor ^ (attempts_so_far - 1))`. In other words, the first retry (after the 1st failure, attempts_so_far becomes 1) waits `base_delay_ms`. The second retry waits `base_delay_ms * backoff_factor`. The third waits `base_delay_ms * backoff_factor^2`, etc.
5. Schedule the next tick if `tick_interval_ms != :infinity`.

Important: `max_attempts` is the **total** number of attempts, not the number of retries. If `max_attempts: 3`, the job will be attempted at most 3 times total (1 initial + 2 retries). A job that succeeds on its first attempt never enters backoff.

Each job's state should include at minimum: `mfa`, `status`, `attempts_so_far`, `next_attempt_at`, `max_attempts`, `base_delay_ms`, `backoff_factor`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.