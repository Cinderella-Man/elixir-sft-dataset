Write me an Elixir GenServer module called `SlidingCounter` that counts events
in a sliding time window using a sub-bucket strategy.

I need these functions in the public API:
- `SlidingCounter.start_link(opts)` to start the process. It should accept:
  - `:clock` — a zero-arity function returning the current time in milliseconds.
    Defaults to `fn -> System.monotonic_time(:millisecond) end`.
  - `:bucket_ms` — the width of each internal sub-bucket in milliseconds.
    Defaults to `1_000` (1 second).
  - `:name` — optional process registration name.
  - `:cleanup_interval_ms` — how often to run the periodic cleanup.
    Defaults to `60_000`. Pass `:infinity` to disable.
- `SlidingCounter.increment(server, key)` — records one event for the given key
  at the current clock time. Returns `:ok`.
- `SlidingCounter.count(server, key, window_ms)` — returns the total number of
  events recorded for `key` that fall within the last `window_ms` milliseconds
  relative to the current clock time. Events outside that window must not be
  counted.

Internal design requirements:
- Divide time into fixed-width sub-buckets of `:bucket_ms` each. Every event is
  placed into the bucket whose index is `div(timestamp, bucket_ms)`.
- When answering `count/3`, only include buckets whose time range overlaps the
  sliding window `[now - window_ms, now]`. Discard (do not count) any bucket
  that falls entirely before the window.
- Different keys must be tracked independently — incrementing "page:home" must
  not affect "page:about".
- Memory must not leak: run a periodic cleanup (via `Process.send_after`) that
  removes all buckets — and whole keys — that have fallen outside a reasonable
  maximum window. Also handle a `:cleanup` message sent directly to the process
  so tests can trigger cleanup synchronously. After cleanup, `state.keys` must
  be an empty map when all data has expired.

Give me the complete module in a single file. Use only the OTP standard library,
no external dependencies.