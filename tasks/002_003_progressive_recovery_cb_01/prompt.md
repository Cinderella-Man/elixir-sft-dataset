Write me an Elixir GenServer module called `ProgressiveRecoveryCircuitBreaker` that implements a **four-state** circuit breaker where recovery is gradual rather than instantaneous.

The motivation: in a standard three-state breaker, a single successful probe in half-open state flips the circuit back to fully closed. If the underlying service is flaky but not fully healed, this causes rapid re-tripping (flapping). This variant adds a new state — `:recovering` — between half-open and closed. After a successful probe, the circuit enters a multi-stage recovery process with increasing call volumes and increasing (but still strict) failure tolerance at each stage. Only after clearing the final stage does the circuit return to fully closed.

States: `:closed` (normal), `:open` (fail fast), `:half_open` (single probe), `:recovering` (progressive rebuild of trust).

API:

- `ProgressiveRecoveryCircuitBreaker.start_link(opts)` with options:
  - `:name` — required process registration name
  - `:failure_threshold` — consecutive failures in closed state before tripping (default 5)
  - `:reset_timeout_ms` — time to stay open before moving to half-open (default 30_000)
  - `:half_open_max_probes` — probes allowed in half-open (default 1)
  - `:recovery_stages` — a list of `{calls_required, failures_tolerated}` tuples defining the recovery ladder. After a successful half-open probe, the circuit enters the first stage. Each stage requires the specified number of calls to complete, tolerating at most the specified number of failures during that stage. Clearing the last stage transitions to `:closed`. Exceeding tolerance at any stage transitions back to `:open`. Default: `[{5, 0}, {15, 1}, {30, 2}]` — first prove 5 calls with zero failures, then 15 calls with at most 1 failure, then 30 calls with at most 2 failures.
  - `:clock` — zero-arity function returning current time in milliseconds (default `fn -> System.monotonic_time(:millisecond) end`)

- `ProgressiveRecoveryCircuitBreaker.call(name, func)` where `func` is a zero-arity function:
  - **Closed**: execute `func`; on success reset the consecutive failure count; on failure increment it and trip to `:open` if it reaches `failure_threshold`. Return whatever `func` returned (or `{:error, exception}` if it raised).
  - **Open**: return `{:error, :circuit_open}` immediately. Transition to `:half_open` once `reset_timeout_ms` has elapsed.
  - **Half-open**: allow up to `half_open_max_probes` calls through. Probe success → `:recovering` (starting at stage 0). Probe failure → `:open` with a restarted reset timer.
  - **Recovering**: every call executes normally. Track calls completed and failures within the current stage. If `stage_failures > failures_tolerated`, transition to `:open` with the reset timer restarted. When `stage_calls >= calls_required`, advance to the next stage (with fresh counters) — or transition to `:closed` if already at the final stage.

- `ProgressiveRecoveryCircuitBreaker.state(name)` returns `:closed | :open | :half_open | :recovering`.

- `ProgressiveRecoveryCircuitBreaker.reset(name)` manually resets to `:closed` with all counters zeroed (failure count, stage counters, recovery stage index).

Outcome classification is the same as a standard breaker: `{:ok, value}` is a success; `{:error, reason}` or a raised exception is a failure. On raise, catch and return `{:error, exception_struct}` without crashing the GenServer. Any other return shape is also a failure.

Single file, no external dependencies.