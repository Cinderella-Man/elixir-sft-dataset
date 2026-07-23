Hey — I need you to write me an Elixir GenServer module called `ProgressiveRecoveryCircuitBreaker`. It's a **four-state** circuit breaker, and the whole point is that recovery is gradual rather than instantaneous.

Here's why I want it: in a standard three-state breaker, a single successful probe in half-open state flips the circuit straight back to fully closed. If the underlying service is flaky but not fully healed, that causes rapid re-tripping — flapping. So this variant adds a new state, `:recovering`, sitting between half-open and closed. After a successful probe, instead of snapping shut, the circuit enters a multi-stage recovery process with increasing call volumes and increasing (but still strict) failure tolerance at each stage. Only after clearing the final stage does the circuit return to fully closed.

The states I want are: `:closed` (normal), `:open` (fail fast), `:half_open` (single probe), and `:recovering` (progressive rebuild of trust).

For the API, start with `ProgressiveRecoveryCircuitBreaker.start_link(opts)`, and it should take these options:

- `:name` — required process registration name.
- `:failure_threshold` — consecutive failures in closed state before tripping (default 5).
- `:reset_timeout_ms` — time to stay open before moving to half-open (default 30_000).
- `:half_open_max_probes` — probes allowed in half-open (default 1).
- `:recovery_stages` — a list of `{calls_required, failures_tolerated}` tuples defining the recovery ladder. After a successful half-open probe, the circuit enters the first stage. Each stage requires the specified number of calls to complete, tolerating at most the specified number of failures during that stage. Clearing the last stage transitions to `:closed`. Exceeding tolerance at any stage transitions back to `:open`. Default: `[{5, 0}, {15, 1}, {30, 2}]` — so first prove 5 calls with zero failures, then 15 calls with at most 1 failure, then 30 calls with at most 2 failures.
- `:clock` — zero-arity function returning current time in milliseconds (default `fn -> System.monotonic_time(:millisecond) end`).

Then `ProgressiveRecoveryCircuitBreaker.call(name, func)`, where `func` is a zero-arity function. Here's how each state should behave:

- **Closed**: execute `func`; on success reset the consecutive failure count; on failure increment it and trip to `:open` if it reaches `failure_threshold` (i.e. the count `>=` the threshold). Return whatever `func` returned (or `{:error, exception}` if it raised).
- **Open**: return `{:error, :circuit_open}` immediately without executing `func`. Transition to `:half_open` once at least `reset_timeout_ms` has elapsed since the circuit opened (elapsed `>=` `reset_timeout_ms`). This elapsed check is measured against `:clock` and is evaluated on demand, so a bare `state(name)` query — with no intervening `call` — will report `:half_open` once enough time has passed.
- **Half-open**: allow up to `half_open_max_probes` calls through as probes. A call that exceeds the probe budget (including the case where `half_open_max_probes` is 0) returns `{:error, :circuit_open}` without executing `func` and leaves the circuit in `:half_open`. Probe success → `:recovering` (starting at stage 0). Probe failure → `:open` with a restarted reset timer (the elapsed clock is measured from this new open transition). A probe returns whatever `func` returned.
- **Recovering**: every call executes normally, returning whatever `func` returned (or `{:error, exception}` if it raised), exactly as in the closed state. Track calls completed and failures within the current stage. If `stage_failures > failures_tolerated`, transition to `:open` with the reset timer restarted (checked before the advance condition). When `stage_calls >= calls_required`, advance to the next stage (with fresh counters) — or transition to `:closed` if already at the final stage.

I also want `ProgressiveRecoveryCircuitBreaker.state(name)` returning `:closed | :open | :half_open | :recovering`, and `ProgressiveRecoveryCircuitBreaker.reset(name)` which manually resets to `:closed` with all counters zeroed (failure count, stage counters, recovery stage index).

Outcome classification should be the same as a standard breaker: `{:ok, value}` is a success; `{:error, reason}` or a raised exception is a failure. On raise, catch and return `{:error, exception_struct}` without crashing the GenServer (e.g. a raised `RuntimeError` yields `{:error, %RuntimeError{message: "boom"}}`). Any other return shape is also a failure.

Keep it to a single file, no external dependencies.
