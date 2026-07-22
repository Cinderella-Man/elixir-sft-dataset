Write me an Elixir GenServer module called `LeakyBucketCircuitBreaker` that tracks failures using a **leaky bucket** instead of a consecutive counter.

The motivation: a consecutive-failure breaker can't distinguish "5 failures in the last second" from "5 failures spread over an hour." The second pattern is benign background noise; the first is an outage. A leaky bucket accumulates failure drops continuously and leaks them at a constant rate, which naturally handles both cases — a burst of failures fills the bucket faster than it can leak (trip), while sustained low-rate failures leak out faster than they arrive (stay closed). The same underlying mechanism is used in networking gear like Cisco routers for error-rate detection.

States are the standard three: closed (normal), open (fail fast), half-open (cautious probing).

API:

- `LeakyBucketCircuitBreaker.start_link(opts)` with options:
  - `:name` — required process registration name
  - `:bucket_capacity` — trip threshold; when bucket level reaches this, transition to `:open` (default 5.0)
  - `:leak_rate_per_sec` — how fast drops leak out, in units per second (default 1.0)
  - `:failure_weight` — drops added to the bucket per failure (default 1.0). Successes don't add anything.
  - `:reset_timeout_ms` — time to stay open before half-open (default 30_000)
  - `:half_open_max_probes` — probes allowed in half-open (default 1)
  - `:clock` — zero-arity function returning current time in milliseconds (default `fn -> System.monotonic_time(:millisecond) end`)

- `LeakyBucketCircuitBreaker.call(name, func)` — standard circuit breaker semantics. In `:closed`:
  1. First apply the leak since the last update: `leak = elapsed_ms * leak_rate_per_sec / 1000`, then `bucket_level = max(0.0, bucket_level - leak)`, and advance `last_update_at` to now.
  2. Execute `func`.
  3. On failure, add `failure_weight` drops to the bucket. On success, do nothing to the bucket.
  4. If the bucket level has reached `bucket_capacity`, transition to `:open` (reset the bucket to 0 on trip so the probe-cycle starts fresh).

  In `:open`, return `{:error, :circuit_open}` immediately. Transition to `:half_open` once `reset_timeout_ms` has elapsed. In `:half_open`, allow up to `half_open_max_probes` calls through — a successful probe returns to `:closed` with an empty bucket; a failed probe returns to `:open`.

- `LeakyBucketCircuitBreaker.state(name)` returns `:closed | :open | :half_open`.

- `LeakyBucketCircuitBreaker.reset(name)` manually resets to `:closed` with an empty bucket.

- `LeakyBucketCircuitBreaker.bucket_level(name)` — inspection API that returns the current leak-adjusted bucket level as a float. This is useful for metrics and debugging. It must apply the pending leak before returning (so the caller always sees a fresh value).

Outcome classification: `{:ok, value}` is a success; `{:error, reason}` or a raised exception is a failure; any other return shape is a failure. On raise, catch and return `{:error, exception_struct}` without crashing the GenServer.

The leak computation must happen lazily on every call that touches the bucket (not via a periodic timer). All bucket arithmetic should be in floats — integer options like `bucket_capacity: 5` should still work and must be coerced.

Single file, no external dependencies.