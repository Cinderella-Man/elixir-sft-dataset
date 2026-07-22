Write me an Elixir GenServer module called `RollingRateCircuitBreaker` that implements the circuit breaker pattern, but trips based on **error rate over a rolling window of recent calls** instead of consecutive failure count.

The motivation: a consecutive-count breaker won't trip on a service that alternates success/failure 50/50, even though such a service is clearly unhealthy. Tracking a rolling window of outcomes and tripping on error rate is the approach used by Netflix Hystrix and similar production breakers. A single success in the middle of a stream of failures shouldn't reset the failure record.

The three states are the same as a standard circuit breaker: closed (normal), open (fail fast), half-open (cautious probing). Only the trip decision changes.

Single file, no external dependencies.

## API

### `RollingRateCircuitBreaker.start_link(opts)`

Starts and registers the breaker. Options:

- `:name` — **required** process registration name. Absent → raise (a missing required key, not a graceful error tuple).
- `:window_size` — number of most recent call outcomes to retain; older outcomes are evicted. Default `20`.
- `:error_rate_threshold` — float in `(0.0, 1.0]`. Default `0.5`.
- `:min_calls_in_window` — minimum number of outcomes currently in the window before the rate is evaluated at all. Default `10`.
- `:reset_timeout_ms` — how long the breaker stays open before it is eligible to become half-open. Default `30_000`.
- `:half_open_max_probes` — probes admitted while half-open. Default `1`.
- `:clock` — zero-arity function returning the current time in milliseconds. Default `fn -> System.monotonic_time(:millisecond) end`. This is the *only* time source the module uses; there are no `Process.send_after` timers, so an injected clock fully controls the breaker's notion of time.

Unknown options are ignored. The breaker starts in `:closed` with an empty outcome window.

### `RollingRateCircuitBreaker.call(name, func)`

`func` is a zero-arity function. Calls are serialized through the GenServer and `func` runs inside the breaker process.

**Outcome classification and return value.** The breaker classifies each execution as a success or a failure, and the caller gets back:

| `func` does | classified as | `call/2` returns |
|---|---|---|
| returns `{:ok, value}` | success | that exact `{:ok, value}` tuple, unchanged |
| returns `{:error, reason}` | failure | that exact `{:error, reason}` tuple, unchanged |
| returns anything else (e.g. `:ok`, `42`, `nil`) | failure | `{:error, {:unexpected_return, other}}` where `other` is the raw value |
| raises an exception | failure | `{:error, exception_struct}` — the rescued exception struct itself; the GenServer must not crash |

**Closed state.** Execute `func`, prepend its outcome to the rolling window (window keeps at most `window_size` outcomes, newest first, oldest evicted), then re-evaluate the trip condition against the *post-append* window:

> trip when `total >= min_calls_in_window` **and** `error_count / total >= error_rate_threshold`, where `total` is the number of outcomes currently in the window (never more than `window_size`).

Both comparisons are inclusive: exactly `min_calls_in_window` outcomes is enough evidence, and a rate exactly equal to `error_rate_threshold` trips. `total == 0` never trips. If `min_calls_in_window > window_size` the window can never reach the floor, so the breaker never trips on its own — that combination is legal and simply disables automatic tripping.

On trip: state becomes `:open`, the moment of tripping is stamped from `:clock`, and the window is emptied. The caller still receives the result of the `func` call that caused the trip (the tripping call is not swallowed).

**Open state.** Return `{:error, :circuit_open}` immediately without executing `func`. No outcome is recorded.

**Open → half-open.** There is no timer. Every `call/2` and every `state/1` first checks, when the breaker is open, whether `clock.() - opened_at >= reset_timeout_ms`; if so the breaker transitions to `:half_open` (probe counter zeroed) *before* the request is handled. The boundary is inclusive: elapsed time exactly equal to `reset_timeout_ms` is enough. Because the check is lazy, a breaker whose timeout has elapsed but which nobody has called is still internally open — the very next `call/2` or `state/1` observes and performs the transition.

**Half-open state.** Up to `half_open_max_probes` probes may be in flight; a call arriving when the in-flight probe count is already at the maximum returns `{:error, :circuit_open}` without executing `func`. Otherwise the probe executes and resolves the state immediately:

- probe classified as success → state becomes `:closed`, window emptied, probe counter zeroed.
- probe classified as failure → state becomes `:open`, the open timestamp is re-stamped from `:clock` (the reset timeout restarts from the failed probe, not from the original trip), window emptied, probe counter zeroed.

Note the consequence of serialized calls: each probe resolves the state before the next request is handled, so a half-open breaker never actually sees a second concurrent probe. Probe outcomes are *not* appended to the outcome window — the rate rule is a closed-state rule only, and one failed probe re-opens the breaker regardless of `min_calls_in_window`.

### `RollingRateCircuitBreaker.state(name)`

Returns `:closed | :open | :half_open`. It performs the open→half-open expiry check described above (so it can itself be the call that flips an expired open breaker to `:half_open`), but it never executes a probe and never consumes a probe slot.

### `RollingRateCircuitBreaker.reset(name)`

Returns `:ok`. From any state, forces the breaker to `:closed`, empties the outcome window, clears the open timestamp, and zeroes the probe counter. Calling it on an already-closed breaker is not a no-op: it discards whatever failures had accumulated in the window. Repeated calls are idempotent.

## Invariants

Every state transition wipes the outcome window, so each new state starts with a clean slate: closed → open on trip, half-open → closed on probe success, half-open → open on probe failure, and manual reset. A breaker that has just tripped, just closed from a probe, or just been reset therefore needs a fresh `min_calls_in_window` outcomes before it can trip again.
