# CircuitBreaker GenServer — circuit breaker pattern

Single-file Elixir module `CircuitBreaker` (a GenServer) implementing the circuit breaker pattern with three states: closed (normal operation), open (fail fast without calling the function), half-open (cautiously probe to see if the problem is fixed). No external dependencies.

**`CircuitBreaker.start_link(opts)`** — starts the GenServer. Options:
- `:name` — process registration name (required)
- `:failure_threshold` — failures in closed state before tripping to open (default 5)
- `:reset_timeout_ms` — time to stay open before moving to half-open (default 30_000)
- `:half_open_max_probes` — calls allowed through in half-open state (default 1)
- `:clock` — zero-arity function returning current time in milliseconds, defaults to `fn -> System.monotonic_time(:millisecond) end`

**`CircuitBreaker.call(name, func)`** — `func` is a zero-arity function representing the protected operation. Behavior by state:
- **Closed**: Execute `func`. If it returns `{:ok, result}`, return `{:ok, result}`. If it returns `{:error, reason}` or raises, count as a failure. If failures reach the threshold, transition to open. Return whatever `func` returned (or `{:error, reason}` if it raised) — even on the call that trips the breaker, return the function's result, not `{:error, :circuit_open}`.
- **Open**: Do not execute `func`. Immediately return `{:error, :circuit_open}`. If at least `reset_timeout_ms` has elapsed since entering the open state (elapsed `>= reset_timeout_ms`, so exactly `reset_timeout_ms` counts), transition to half-open instead and let this call through as a probe.
- **Half-open**: Allow up to `half_open_max_probes` calls through. On probe success, transition back to closed and reset failure count. On probe failure, transition back to open and restart the reset timeout (measured from the current clock reading, so the next call fails fast until another full `reset_timeout_ms` elapses). Calls beyond the probe limit get `{:error, :circuit_open}`.

**`CircuitBreaker.state(name)`** — returns current state atom: `:closed`, `:open`, or `:half_open`.

**`CircuitBreaker.reset(name)`** — manually reset to closed state with zero failure count, regardless of current state.

**Success/failure semantics:**
- Success = `func` returns `{:ok, value}`.
- Failure = `func` returns `{:error, reason}` or raises an exception.
- A success in closed state resets the failure count to zero, so only consecutive failures accumulate toward the threshold.
- When `func` raises, catch it and return `{:error, %RuntimeError{message: ...}}` or whatever the exception was (returned as the exception struct itself); do not let it crash the GenServer.
