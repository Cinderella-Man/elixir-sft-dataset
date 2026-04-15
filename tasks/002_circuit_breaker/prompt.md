Write me an Elixir GenServer module called `CircuitBreaker` that implements the circuit breaker pattern. It should have three states: closed (normal operation), open (failing fast without calling the function), and half-open (cautiously probing to see if the problem is fixed).

Here's the API I need:

- `CircuitBreaker.start_link(opts)` starts the GenServer. Options are:
  - `:name` — process registration name (required)
  - `:failure_threshold` — how many failures in closed state before tripping to open (default 5)
  - `:reset_timeout_ms` — how long to stay open before moving to half-open (default 30_000)
  - `:half_open_max_probes` — how many calls to allow through in half-open state (default 1)
  - `:clock` — a zero-arity function returning current time in milliseconds, defaults to `fn -> System.monotonic_time(:millisecond) end`

- `CircuitBreaker.call(name, func)` where func is a zero-arity function representing the protected operation. Behavior depends on state:
  - **Closed**: Execute the function. If it returns `{:ok, result}`, return `{:ok, result}`. If it returns `{:error, reason}` or raises, count it as a failure. If failures reach the threshold, transition to open. Return whatever the function returned (or `{:error, reason}` if it raised).
  - **Open**: Don't execute the function at all. Immediately return `{:error, :circuit_open}`. If enough time has passed (reset_timeout_ms since entering open state), transition to half-open instead and let this call through as a probe.
  - **Half-open**: Allow up to `half_open_max_probes` calls through. If a probe succeeds, transition back to closed and reset failure count. If a probe fails, transition back to open and restart the reset timeout. Additional calls beyond the probe limit get `{:error, :circuit_open}`.

- `CircuitBreaker.state(name)` returns the current state as an atom: `:closed`, `:open`, or `:half_open`.

- `CircuitBreaker.reset(name)` manually resets the circuit breaker to closed state with zero failure count, regardless of current state.

A success is when `func` returns `{:ok, value}`. A failure is when `func` returns `{:error, reason}` or raises an exception. When the function raises, catch it and return `{:error, %RuntimeError{message: ...}}` or whatever the exception was, but don't let it crash the GenServer.

No external dependencies. Single file with the `CircuitBreaker` module.
