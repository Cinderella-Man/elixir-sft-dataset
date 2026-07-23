# `PenaltyLimiter` — per-key rate limiter with escalating penalties

Single-file Elixir GenServer module `PenaltyLimiter` enforcing per-key sliding-window rate limits plus a second layer of escalating cooldowns for repeat offenders. When a key is rate-limited it earns a "strike"; strikes accumulate, and each strike imposes a cooldown that must elapse before the key can be evaluated against the normal rate limit again. More misbehavior → longer lockout. OTP standard library only, no external dependencies. Deliver the complete module in a single file.

**Public API — `start_link/1`**
- `PenaltyLimiter.start_link(opts)` starts the process.
- Accepts `:clock`, a zero-arity function returning the current time in milliseconds; default `fn -> System.monotonic_time(:millisecond) end`.
- Accepts `:name` for process registration.
- Accepts `:cleanup_interval_ms` (see Cleanup).

**Public API — `check/5`**
- `PenaltyLimiter.check(server, key, max_requests, window_ms, penalty_ladder)` evaluates a request.
- `penalty_ladder` is a list of cooldown durations in milliseconds indexed by strike count, e.g. `[1_000, 5_000, 30_000, 300_000]` means "first strike = 1s cooldown, second = 5s, third = 30s, fourth and beyond = 5min".
- Each key is tracked independently.

**Return values**
- `{:ok, remaining}` — request allowed under the normal sliding-window limit. `remaining` is the number of further requests still allowed in the current window *after* this one — i.e. `max_requests` minus the number of window slots now occupied (first of three allowed requests returns `{:ok, 2}`, then `{:ok, 1}`, then `{:ok, 0}`).
- `{:error, :rate_limited, retry_after_ms, strike_count}` — rejected because the normal limit is exceeded. A strike is recorded. `retry_after_ms` is the larger of (time until the oldest window entry expires) and (the new strike's cooldown from the ladder).
- `{:error, :cooling_down, retry_after_ms, strike_count}` — rejected because an active cooldown from a previous strike is still in effect. No new strike is recorded (do not compound penalties for retrying during a cooldown). `retry_after_ms` is the remaining cooldown.

**Per-key internal state**
- List of request timestamps (for the sliding window).
- Current strike count.
- Time the last strike was issued (for decay calculation).
- Time the current cooldown ends.

**Strike decay**
- Strikes persist across window boundaries and only decay with time.
- A key's strike count drops by one for every `window_ms * 10` that passes with no new strikes. This is not configurable — a fifth argument would overcomplicate the signature; use the `window_ms * 10` rule.
- Decay is evaluated lazily at each `check` call: one strike removed per full `window_ms * 10` period elapsed since the last strike — an elapsed time of exactly one period already removes one strike.
- For each strike removed, the "last strike" reference time advances by one full period (it does not reset to the current time), so further decay stays on the original schedule.

**Decay forgives cooldowns**
- Whenever at least one strike decays, any outstanding cooldown is cancelled and the request is evaluated against the normal sliding-window limit.
- `:cooling_down` is only returned while no strike has decayed since the cooldown was recorded.
- When the strike count decays to zero the key resets entirely, as if never seen.

**Cooldown / window bookkeeping**
- The cooldown recorded with a new strike ends exactly `retry_after_ms` — the value returned in the `:rate_limited` tuple, i.e. the max defined above — after the moment the strike was issued.
- A rejected request's timestamp is not added to the sliding window; only allowed requests consume window slots.

**Cleanup**
- Run a periodic cleanup using `Process.send_after` every 60 seconds, configurable via the `:cleanup_interval_ms` option.
- Cleanup removes keys whose timestamps have all expired AND whose strike count has decayed to zero AND whose cooldown has elapsed — i.e., keys indistinguishable from never-seen keys.
- `:cleanup_interval_ms` may also be `:infinity`, in which case the periodic timer is never scheduled — nothing runs automatically.
- Sending the server process a bare `:cleanup` message performs one cleanup pass immediately — the same work the periodic timer performs.
