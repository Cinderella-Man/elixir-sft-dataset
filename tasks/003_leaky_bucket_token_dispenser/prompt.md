Write me an Elixir GenServer module called `LeakyBucket` that implements a token-based leaky bucket algorithm for traffic shaping.

I need these functions in the public API:

- `LeakyBucket.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

- `LeakyBucket.acquire(server, bucket_name, capacity, refill_rate, tokens \\ 1)` which attempts to drain `tokens` from the named bucket. `capacity` is the maximum number of tokens the bucket can hold, and `refill_rate` is the number of tokens added per second. If enough tokens are available, drain them and return `{:ok, remaining}` where `remaining` is how many tokens are left after the drain. If not enough tokens are available, return `{:error, :empty, retry_after_ms}` where `retry_after_ms` is how many milliseconds the caller should wait before enough tokens have refilled to satisfy the request.

Each bucket name must be tracked independently — draining "api:uploads" should have no effect on "api:downloads". A brand new bucket that has never been seen before should start full at `capacity` tokens.

Token refill must be calculated lazily on each `acquire` call based on elapsed time since the last access, not via a timer per bucket. The formula is: `new_tokens = min(capacity, old_tokens + elapsed_ms * refill_rate / 1000)`. This means if a bucket has 0 tokens, a capacity of 10, and a refill rate of 5 tokens/second, then after 1000ms it should have 5 tokens, and after 2000ms it should be full at 10 (never exceeding capacity).

You also need to make sure stale bucket entries get cleaned up so the GenServer doesn't leak memory over time. Run a periodic cleanup using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) that removes tracking data for any bucket that hasn't been accessed within the last `cleanup_ttl_ms` milliseconds (default 300_000, i.e. 5 minutes). The cleanup should be based on the injectable clock, not wall time.

Store the GenServer state as a struct or map with a `buckets` key that holds a map of bucket_name => bucket_data. Each bucket_data should track at least the current token count (as a float for fractional refills), the last access timestamp, and whatever else you need.

The `remaining` value returned on success should be an integer (floor of the float token count after draining).

The `retry_after_ms` value returned on rejection should be a positive integer representing the ceiling of the time needed to refill enough tokens.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.