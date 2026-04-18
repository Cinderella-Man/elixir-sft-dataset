Write me an Elixir GenServer module called `GcraLimiter` that implements rate limiting using the **Generic Cell Rate Algorithm (GCRA)**.

GCRA is the rate-limiting algorithm used in ATM networks and in modern systems like Redis-Cell. It's mathematically equivalent to a token bucket but uses a completely different state representation: instead of tracking `{tokens, last_refill_at}` per bucket, GCRA tracks a single scalar — the **Theoretical Arrival Time (TAT)**, which is the earliest wall-clock time at which the next request would be admitted if no burst were allowed.

I need these functions in the public API:

- `GcraLimiter.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

- `GcraLimiter.acquire(server, bucket_name, rate_per_sec, burst_size, tokens \\ 1)` which attempts to admit a request of `tokens` units for the named bucket. `rate_per_sec` is the steady-state rate (requests per second); `burst_size` is the maximum burst that's allowed above the steady state (analogous to bucket capacity in token-bucket terms).

  The algorithm works like this. Let `emission_interval = 1000 / rate_per_sec` (ms per single token at the steady rate). Let `delay_variation_tolerance = burst_size * emission_interval` (how far *before* the TAT we'll still admit a request — this is what allows bursts). For each `acquire`:

  1. Fetch the current TAT for the bucket (default: `now` if the bucket is brand new — a fresh bucket admits the full burst immediately).
  2. Compute `new_tat = max(now, tat) + tokens * emission_interval`.
  3. Compute `earliest_admit_time = new_tat - delay_variation_tolerance`.
  4. If `earliest_admit_time <= now`: accept the request. Store `new_tat` as the bucket's TAT. Return `{:ok, remaining}` where `remaining` is the equivalent "tokens left in the burst budget" — specifically `floor((delay_variation_tolerance - (new_tat - now)) / emission_interval)`.
  5. Otherwise: reject. Do NOT update TAT. Return `{:error, :rate_exceeded, retry_after_ms}` where `retry_after_ms = ceil(earliest_admit_time - now)`.

  Two pitfalls the model must avoid:
  - **Forgetting the `max(now, tat)` step**: if the bucket was idle (TAT is in the past), you must reset the baseline to `now`, or you'd "credit" the bucket for idle time beyond the burst tolerance and allow unbounded bursts after a long quiet period.
  - **Updating TAT on rejection**: a rejected request must not advance TAT, or repeated rejected calls would push TAT forward with no corresponding admits, starving legitimate retries.

Each bucket name must be tracked independently. Rate and burst parameters are passed per call (not configured at start_link), matching the original task's pattern.

You also need periodic cleanup via `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option, default 60_000). A bucket is safe to drop when its TAT is far enough in the past that an immediate acquire would behave identically to a fresh bucket — specifically, when `now - tat >= cleanup_idle_ms` (default 300_000ms, configurable via `:cleanup_idle_ms`). Use the injectable clock, not wall time.

The `remaining` value on success is an integer. The `retry_after_ms` value on rejection is a positive integer (minimum 1).

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.