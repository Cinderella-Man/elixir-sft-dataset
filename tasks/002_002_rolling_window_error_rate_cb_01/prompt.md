Write me an Elixir GenServer module called `RollingRateCircuitBreaker` that implements the circuit breaker pattern, but trips based on **error rate over a rolling window of recent calls** instead of consecutive failure count.

The motivation: a consecutive-count breaker won't trip on a service that alternates success/failure 50/50, even though such a service is clearly unhealthy. Tracking a rolling window of outcomes and tripping on error rate is the approach used by Netflix Hystrix and similar production breakers. A single success in the middle of a stream of failures shouldn't reset the failure record.

The three states are the same as a standard circuit breaker: closed (normal), open (fail fast), half-open (cautious probing). Only the trip decision changes.

API:

- `RollingRateCircuitBreaker.start_link(opts)` with options:
  - `:name` — required process registration name
  - `:window_size` — number of most recent calls to track; older outcomes are evicted (default 20)
  - `:error_rate_threshold` — float in `(0.0, 1.0]`. Trip when at least this fraction of the window's calls have failed (default 0.5)
  - `:min_calls_in_window` — minimum call count before evaluating the rate. Below this the circuit stays closed regardless of rate, so a single initial failure can't trip it (default 10)
  - `:reset_timeout_ms` — time to stay open before moving to half-open (default 30_000)
  - `:half_open_max_probes` — probes allowed in half-open (default 1)
  - `:clock` — zero-arity function returning current time in milliseconds (default `fn -> System.monotonic_time(:millisecond) end`)

- `RollingRateCircuitBreaker.call(name, func)` where `func` is a zero-arity function. In closed state, execute and append the outcome (`:ok` or `:error`) to the rolling window. Trip to open when `error_count / total_count >= error_rate_threshold` AND `total_count >= min_calls_in_window`. In open, return `{:error, :circuit_open}` immediately without executing. In half-open, allow up to `half_open_max_probes` calls through; a successful probe returns to closed, a failed probe returns to open.

- `RollingRateCircuitBreaker.state(name)` returns `:closed | :open | :half_open`.

- `RollingRateCircuitBreaker.reset(name)` manually resets to closed with an empty outcome window.

A success is when `func` returns `{:ok, value}`. A failure is when it returns `{:error, reason}` or raises. On raise, catch and return `{:error, exception_struct}` without crashing the GenServer. Any other return shape is also a failure.

Clear the outcome window on every state transition (closed → open on trip, half-open → closed on probe success, half-open → open on probe failure, and manual reset) so each new state starts with a clean slate.

Single file, no external dependencies.