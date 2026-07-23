Hey — could you build me an Elixir GenServer module called `LeakyBucket`? I want it to implement a token-based leaky bucket algorithm for traffic shaping, and I've got a fairly specific shape in mind, so let me walk you through it.

For the public API, I need `LeakyBucket.start_link(opts)` to start the process. It should accept a `:clock` option, which is a zero-arity function returning the current time in milliseconds — if the caller doesn't provide one, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

The other one I need is `LeakyBucket.acquire(server, bucket_name, capacity, refill_rate, tokens \\ 1)`, which attempts to drain `tokens` from the named bucket. Here `capacity` is the maximum number of tokens the bucket can hold, and `refill_rate` is the number of tokens added per second. If enough tokens are available, drain them and return `{:ok, remaining}`, where `remaining` is how many tokens are left after the drain. If there aren't enough tokens available, return `{:error, :empty, retry_after_ms}`, where `retry_after_ms` is how many milliseconds the caller should wait before enough tokens have refilled to satisfy the request.

A couple of behaviors I care about: each bucket name has to be tracked independently — draining "api:uploads" should have no effect on "api:downloads". And a brand new bucket that's never been seen before should start full at `capacity` tokens.

I want the token refill computed lazily on each `acquire` call based on the elapsed time since the last access — please don't use a timer per bucket for this. The formula is `new_tokens = min(capacity, old_tokens + elapsed_ms * refill_rate / 1000)`. So, concretely, if a bucket has 0 tokens, a capacity of 10, and a refill rate of 5 tokens/second, then after 1000ms it should have 5 tokens, and after 2000ms it should be full at 10 (never exceeding capacity).

I also need stale bucket entries to get cleaned up so the GenServer doesn't leak memory over time. Please run a periodic cleanup using `Process.send_after` every 60 seconds (configurable via the `:cleanup_interval_ms` option) that removes tracking data for any bucket that hasn't been accessed within the last `cleanup_ttl_ms` milliseconds (default 300_000, i.e. 5 minutes). Base that cleanup on the injectable clock, not wall time. One extra wrinkle: `:cleanup_interval_ms` may also be `:infinity`, in which case the periodic timer is never scheduled — nothing runs automatically. And if the server process receives a bare `:cleanup` message, it should perform one cleanup pass immediately — the same work the periodic timer performs.

For state, store the GenServer state as a struct or map with a `buckets` key that holds a map of bucket_name => bucket_data. Each bucket_data should track at least the current token count (as a float, so fractional refills work), the last access timestamp, and whatever else you need.

Two more details on the return values: the `remaining` value returned on success should be an integer (the floor of the float token count after draining), and the `retry_after_ms` value returned on rejection should be a positive integer representing the ceiling of the time needed to refill enough tokens.

Give me the complete module in a single file, and please use only the OTP standard library — no external dependencies.
