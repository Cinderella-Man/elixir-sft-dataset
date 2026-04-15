Write me an Elixir GenServer module called `RateLimiter` that enforces per-key rate limits using a sliding window algorithm.

I need these functions in the public API:

- `RateLimiter.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

- `RateLimiter.check(server, key, max_requests, window_ms)` which checks whether a request for the given key is allowed. If allowed, return `{:ok, remaining}` where remaining is how many more requests are available in the current window. If not allowed, return `{:error, :rate_limited, retry_after_ms}` where retry_after_ms tells the caller how long to wait.

Each key must be tracked independently — rate limiting "user:1" should have no effect on "user:2". The sliding window should work correctly at boundaries, meaning if I make 3 requests allowed per 1000ms window and I make them at time 0, then at time 1001 I should be allowed again.

You also need to make sure expired entries get cleaned up so the GenServer doesn't leak memory over time. Run a periodic cleanup using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) that removes any tracking data for windows that have fully expired.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.
