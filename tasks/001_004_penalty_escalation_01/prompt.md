Write me an Elixir GenServer module called `PenaltyLimiter` that enforces per-key rate limits with **escalating penalties** for repeat offenders.

The motivation: simple sliding-window rate limiters let a misbehaving client retry the instant their window clears. This module adds a second layer — when a key gets rate-limited, it earns a "strike." Strikes accumulate, and each strike imposes a cooldown that must elapse before the key can even be evaluated against the normal rate limit again. The more a client misbehaves, the longer they're locked out.

I need these functions in the public API:

- `PenaltyLimiter.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

- `PenaltyLimiter.check(server, key, max_requests, window_ms, penalty_ladder)` which evaluates a request. `penalty_ladder` is a list of cooldown durations in milliseconds indexed by strike count, e.g. `[1_000, 5_000, 30_000, 300_000]` means "first strike = 1s cooldown, second = 5s, third = 30s, fourth and beyond = 5min". Strikes persist across window boundaries and only decay with time — specifically, a key's strike count drops by one for every `window_ms * 10` that passes with no new strikes (configurable via a fifth argument would overcomplicate the signature; use the `window_ms * 10` rule).

  Possible return values:
  - `{:ok, remaining}` — request allowed under the normal sliding-window limit, where `remaining` is the remaining allowance in the current window.
  - `{:error, :rate_limited, retry_after_ms, strike_count}` — request rejected because the normal limit is exceeded. A strike has been recorded. `retry_after_ms` is the larger of (time until the oldest window entry expires) and (the new strike's cooldown from the ladder).
  - `{:error, :cooling_down, retry_after_ms, strike_count}` — request rejected because an active cooldown from a previous strike is still in effect. No new strike is recorded (you don't compound penalties for retrying during a cooldown). `retry_after_ms` is the remaining cooldown.

Each key must be tracked independently. Internally track per key: the list of request timestamps (for the sliding window), the current strike count, the time the last strike was issued (for decay calculation), and the time the current cooldown ends.

Run a periodic cleanup using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) that removes keys whose timestamps have all expired AND whose strike count has decayed to zero AND whose cooldown has elapsed — i.e., keys that are indistinguishable from never-seen keys.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.