Write me an Elixir GenServer module called `SlidingSum` that maintains a sliding
time-window running **sum of numeric amounts** per key, using a sub-bucket
strategy.

Unlike a plain event counter, each recorded event carries a numeric amount
(think bytes transferred, dollars spent, or points scored), and queries return
the total amount within the window rather than a count of events.

I need these functions in the public API:
- `SlidingSum.start_link(opts)` to start the process. It should accept:
  - `:clock` — a zero-arity function returning the current time in milliseconds.
    Defaults to `fn -> System.monotonic_time(:millisecond) end`.
  - `:bucket_ms` — the width of each internal sub-bucket in milliseconds.
    Defaults to `1_000` (1 second).
  - `:name` — optional process registration name.
  - `:cleanup_interval_ms` — how often to run the periodic cleanup.
    Defaults to `60_000`. Pass `:infinity` to disable.
- `SlidingSum.add(server, key, amount)` — records `amount` (any number: it may be
  an integer or a float, and it may be negative) for the given key at the current
  clock time. Returns `:ok`.
- `SlidingSum.sum(server, key, window_ms)` — returns the total of all amounts
  recorded for `key` that fall within the last `window_ms` milliseconds relative
  to the current clock time. Amounts outside that window must not be included.
- `SlidingSum.keys(server)` — returns the list of keys currently tracked (those
  that still have at least one stored bucket), in no particular order. A server
  with no data returns `[]`, and once cleanup has removed every bucket of a key,
  that key no longer appears.

Semantics and internal design requirements:
- A key that has had no amounts added returns a sum of `0`.
- Divide time into fixed-width sub-buckets of `:bucket_ms` each. Every event is
  placed into the bucket whose index is `div(timestamp, bucket_ms)`, and each
  bucket accumulates the sum of the amounts placed into it.
- When answering `sum/3`, include a bucket iff its start time falls within the
  sliding window — that is, include bucket `b` iff `b * bucket_ms >= now - window_ms`.
  Discard (do not include) any bucket that starts before the window.
- Negative amounts subtract from the running window sum; a sum may therefore be
  negative or zero.
- Different keys must be tracked independently — adding to `"conn:a"` must not
  affect `"conn:b"`.
- Memory must not leak: the GenServer state must store per-key bucket sums under
  `state.keys`. Run a periodic cleanup (via `Process.send_after`) that removes
  buckets — and whole keys — that have fallen outside a reasonable maximum
  window. Also handle a `:cleanup` message sent directly to the process so tests
  can trigger cleanup synchronously. After cleanup, `state.keys` must be an empty
  map when all data has expired.

Give me the complete module in a single file. Use only the OTP standard library,
no external dependencies.