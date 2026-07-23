# `SlidingSum` — sliding-window sum-of-amounts GenServer

Implement an Elixir GenServer module `SlidingSum` that maintains a sliding time-window running **sum of numeric amounts** per key, using a sub-bucket strategy. Unlike a plain event counter, each recorded event carries a numeric amount (bytes transferred, dollars spent, points scored), and queries return the total amount within the window rather than a count of events.

**Public API — startup**
- `SlidingSum.start_link(opts)` starts the process.
- `:clock` — a zero-arity function returning the current time in milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
- `:bucket_ms` — width of each internal sub-bucket in milliseconds. Defaults to `1_000` (1 second).
- `:name` — optional process registration name.
- `:cleanup_interval_ms` — how often the periodic cleanup runs. Defaults to `60_000`. Pass `:infinity` to disable.

**Public API — operations**
- `SlidingSum.add(server, key, amount)` — records `amount` for the given key at the current clock time. Returns `:ok`. `amount` may be any number: integer or float, and it may be negative.
- `SlidingSum.sum(server, key, window_ms)` — returns the total of all amounts recorded for `key` that fall within the last `window_ms` milliseconds relative to the current clock time. Amounts outside that window must not be included.
- `SlidingSum.keys(server)` — returns the list of keys currently tracked (those that still have at least one stored bucket), in no particular order. A server with no data returns `[]`; once cleanup has removed every bucket of a key, that key no longer appears.

**Bucketing semantics**
- Time is divided into fixed-width sub-buckets of `:bucket_ms` each.
- Every event is placed into the bucket whose index is `div(timestamp, bucket_ms)`; each bucket accumulates the sum of the amounts placed into it.
- For `sum/3`, include a bucket iff its start time falls within the sliding window — i.e. include bucket `b` iff `b * bucket_ms >= now - window_ms`. Discard (do not include) any bucket that starts before the window.

**Value and isolation semantics**
- A key that has had no amounts added returns a sum of `0`.
- Negative amounts subtract from the running window sum; a sum may therefore be negative or zero.
- Keys are tracked independently — adding to `"conn:a"` must not affect `"conn:b"`.

**Retention / cleanup**
- No memory leaks: GenServer state stores per-key bucket sums under `state.keys`.
- A periodic cleanup (scheduled via `Process.send_after`) removes buckets — and whole keys — that have fallen outside the maximum retention window of **24 hours** (`24 * 60 * 60 * 1000` ms).
- Cleanup retains a bucket exactly when its start time satisfies the same inclusive rule as `sum/3`, i.e. `bucket_start >= now - 86_400_000`; a bucket starting exactly on that horizon survives.
- Handle a `:cleanup` message sent directly to the process so tests can trigger cleanup synchronously.
- After cleanup, `state.keys` must be an empty map when all data has expired.

**Delivery**
- Complete module in a single file.
- OTP standard library only, no external dependencies.
