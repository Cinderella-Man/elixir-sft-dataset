Write me an Elixir GenServer module called `HierarchicalLimiter` that enforces **multiple simultaneous** rate limits per key using a sliding window algorithm.

The motivation: real APIs often advertise tiered limits like "10 requests/second AND 100 requests/minute AND 1000 requests/hour". A request is only allowed if it passes **every** tier. This module enforces all tiers against the same stream of request timestamps.

I need these functions in the public API:

- `HierarchicalLimiter.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

- `HierarchicalLimiter.check(server, key, tiers)` where `tiers` is a non-empty list of `{tier_name, max_requests, window_ms}` tuples. For example: `[{:per_second, 10, 1_000}, {:per_minute, 100, 60_000}, {:per_hour, 1000, 3_600_000}]`. The tier_name is an atom used for reporting which tier was exceeded. If the request passes every tier, return `{:ok, remaining_by_tier}` where `remaining_by_tier` is a map like `%{per_second: 7, per_minute: 94, per_hour: 893}` — the remaining allowance under each tier after accepting this request. If any tier would be exceeded, return `{:error, :rate_limited, tier_name, retry_after_ms}` identifying the tightest tier that rejected the request and how long until that specific tier would admit a new request. "Tightest" means the tier with the longest retry_after (i.e., the tier the caller needs to wait on). Do not record the timestamp when the request is rejected — a rejected request should not consume budget under any tier.

Each key must be tracked independently. Internally, keep a single list of timestamps per key (shared across tiers) and evaluate each tier against that list by counting entries within the tier's window. The widest tier's window determines how long timestamps must be retained; timestamps older than the widest window can be discarded.

You also need to make sure expired entries get cleaned up so the GenServer doesn't leak memory over time. Run a periodic cleanup using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) that prunes timestamps older than the widest window seen for each key, and drops keys whose timestamp list becomes empty.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.