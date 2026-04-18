Write me an Elixir GenServer module called `FixedWindowLimiter` that enforces per-key rate limits using a fixed-window counter algorithm.

I need these functions in the public API:

- `FixedWindowLimiter.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

- `FixedWindowLimiter.check(server, key, max_requests, window_ms)` which checks whether a request for the given key is allowed. The algorithm works by snapping time into discrete fixed windows: the window a timestamp belongs to is `div(timestamp, window_ms)`. Each `{key, window_index}` pair has an independent counter. If the counter for the current window is below max_requests, the request is allowed and the counter is incremented — return `{:ok, remaining}`. If the counter has reached max_requests, return `{:error, :rate_limited, retry_after_ms}` where retry_after_ms is the time until the current window ends (when the counter resets).

Each key must be tracked independently — rate limiting "user:1" should have no effect on "user:2". Windows are absolute, not relative: with a 1000ms window, timestamps 0-999 belong to window 0, 1000-1999 belong to window 1, and so on. This means the counter resets abruptly at window boundaries. Note that this is a known property of fixed-window counters: a client could send max_requests at t=999 and max_requests again at t=1000, effectively doubling the rate at the boundary. That behavior is acceptable for this implementation — do not try to smooth it out.

You also need to make sure expired counter entries get cleaned up so the GenServer doesn't leak memory over time. Run a periodic cleanup using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) that removes any counter whose window has fully ended (window_end_time < current time).

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.