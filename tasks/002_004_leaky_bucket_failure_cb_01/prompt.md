# Design Brief: `LeakyBucketCircuitBreaker`

## Problem

A consecutive-failure circuit breaker can't distinguish "5 failures in the last second" from "5 failures spread over an hour." The second pattern is benign background noise; the first is an outage. We need a breaker that tells these apart.

The solution is a **leaky bucket** instead of a consecutive counter. A leaky bucket accumulates failure drops continuously and leaks them at a constant rate, which naturally handles both cases — a burst of failures fills the bucket faster than it can leak (trip), while sustained low-rate failures leak out faster than they arrive (stay closed). The same underlying mechanism is used in networking gear like Cisco routers for error-rate detection.

## Constraints

- Deliver an Elixir GenServer module called `LeakyBucketCircuitBreaker` that tracks failures using a leaky bucket.
- States are the standard three: closed (normal), open (fail fast), half-open (cautious probing).
- The leak computation must happen lazily on every call that touches the bucket (not via a periodic timer).
- All bucket arithmetic should be in floats — integer options like `bucket_capacity: 5` should still work and must be coerced.
- On a raised exception, catch and return `{:error, exception_struct}` without crashing the GenServer.
- Single file, no external dependencies.

**Outcome classification:** `{:ok, value}` is a success; `{:error, reason}` or a raised exception is a failure; any other return shape is a failure.

## Required Interface

1. `LeakyBucketCircuitBreaker.start_link(opts)` with options:
   - `:name` — required process registration name
   - `:bucket_capacity` — trip threshold; when bucket level reaches this, transition to `:open` (default 5.0)
   - `:leak_rate_per_sec` — how fast drops leak out, in units per second (default 1.0)
   - `:failure_weight` — drops added to the bucket per failure (default 1.0). Successes don't add anything.
   - `:reset_timeout_ms` — time to stay open before half-open (default 30_000)
   - `:half_open_max_probes` — probes allowed in half-open (default 1)
   - `:clock` — zero-arity function returning current time in milliseconds (default `fn -> System.monotonic_time(:millisecond) end`)

2. `LeakyBucketCircuitBreaker.call(name, func)` — standard circuit breaker semantics. Whenever `func` is actually executed, `call` returns `func`'s own return value unchanged — `{:ok, value}` on a success, `{:error, reason}` on a failing tuple — except on a raised exception, where it catches and returns `{:error, exception_struct}` (the raised exception struct itself, e.g. `{:error, %RuntimeError{message: "boom"}}`).
   - In `:closed`:
     1. First apply the leak since the last update: `leak = elapsed_ms * leak_rate_per_sec / 1000`, then `bucket_level = max(0.0, bucket_level - leak)`, and advance `last_update_at` to now.
     2. Execute `func`.
     3. On failure, add `failure_weight` drops to the bucket. On success, do nothing to the bucket.
     4. If the bucket level has reached `bucket_capacity` (i.e. `>=`), transition to `:open` (reset the bucket to 0 on trip so the probe-cycle starts fresh).
   - In `:open`, return `{:error, :circuit_open}` immediately without executing `func`. Transition to `:half_open` once `reset_timeout_ms` has elapsed (`>=`); this transition is lazy — a call to `state/1` after the timeout must itself report `:half_open` with no intervening `call`.
   - In `:half_open`, allow up to `half_open_max_probes` calls through — a successful probe returns to `:closed` with an empty bucket; a failed probe returns to `:open` and restarts the reset timeout.

3. `LeakyBucketCircuitBreaker.state(name)` returns `:closed | :open | :half_open`.

4. `LeakyBucketCircuitBreaker.reset(name)` manually resets to `:closed` with an empty bucket.

5. `LeakyBucketCircuitBreaker.bucket_level(name)` — inspection API that returns the current leak-adjusted bucket level as a float. This is useful for metrics and debugging. It must apply the pending leak before returning (so the caller always sees a fresh value).

## Acceptance Criteria

- A burst of failures fills the bucket faster than it can leak and trips the breaker; sustained low-rate failures leak out faster than they arrive and keep it closed.
- When `func` is executed, `call` returns `func`'s own value unchanged: `{:ok, value}` on success and `{:error, reason}` on a failing tuple; on a raised exception it returns `{:error, exception_struct}` (the raised struct itself) without crashing the GenServer.
- Outcome classification holds: `{:ok, value}` counts as a success; `{:error, reason}` or a raised exception counts as a failure; any other return shape counts as a failure.
- In `:closed`, each call applies the leak first (`leak = elapsed_ms * leak_rate_per_sec / 1000`, then `bucket_level = max(0.0, bucket_level - leak)`, advancing `last_update_at`), executes `func`, adds `failure_weight` on failure (nothing on success), and trips to `:open` when the level is `>=` `bucket_capacity`, resetting the bucket to 0 on trip.
- In `:open`, calls return `{:error, :circuit_open}` immediately without executing `func`, and the breaker transitions to `:half_open` lazily once `reset_timeout_ms` has elapsed (`>=`) — including a bare `state/1` call after the timeout reporting `:half_open` with no intervening `call`.
- In `:half_open`, up to `half_open_max_probes` calls pass through; a successful probe returns to `:closed` with an empty bucket, and a failed probe returns to `:open` and restarts the reset timeout.
- `state/1`, `reset/1`, and `bucket_level/1` behave as specified, with `bucket_level/1` applying the pending leak before returning a fresh float.
- The leak is computed lazily on every call that touches the bucket (no periodic timer), all bucket arithmetic is in floats, and integer options such as `bucket_capacity: 5` work and are coerced.
- Delivered as a single file with no external dependencies.
