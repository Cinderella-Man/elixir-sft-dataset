Write me an Elixir GenServer module called `SlidingAlerter` that watches a
sliding-window event rate per key and reports an alarm state when the rate
crosses a configured threshold — a self-clearing threshold detector built on a
sub-bucket sliding window.

I need these functions in the public API:
- `SlidingAlerter.start_link(opts)` to start the process. It should accept:
  - `:clock` — a zero-arity function returning the current time in milliseconds.
    Defaults to `fn -> System.monotonic_time(:millisecond) end`.
  - `:bucket_ms` — the width of each internal sub-bucket in milliseconds.
    Defaults to `1_000` (1 second).
  - `:threshold` — the event count within the alerting window at or above which
    a key is considered to be in alarm. Defaults to `5`.
  - `:window_ms` — the sliding alerting window width in milliseconds. Defaults to
    `60_000`.
  - `:name` — optional process registration name.
  - `:cleanup_interval_ms` — how often to run the periodic cleanup.
    Defaults to `60_000`. Pass `:infinity` to disable.
- `SlidingAlerter.record(server, key)` — records one event for the given key at
  the current clock time, then returns the key's resulting status (`:ok` or
  `:alarm`).
- `SlidingAlerter.status(server, key)` — returns `:ok` or `:alarm` for the key
  based on the current clock time, without recording anything.
- `SlidingAlerter.count(server, key)` — returns the number of events recorded for
  the key that fall within the last `:window_ms` milliseconds relative to the
  current clock time.

Status and counting semantics:
- A key's status is `:alarm` when the number of events for that key within the
  last `:window_ms` milliseconds is greater than or equal to `:threshold`;
  otherwise the status is `:ok`.
- A key that has never been recorded has a count of `0` and status `:ok`.
- The alarm is self-clearing: as events slide out of the window, the count falls,
  and once it drops below `:threshold` the status returns to `:ok` with no
  explicit reset.
- Time is divided into fixed-width sub-buckets of `:bucket_ms` each; every event
  is placed into the bucket whose index is `div(timestamp, bucket_ms)`. When
  computing the count for the alerting window, include a bucket iff its start time
  `b * bucket_ms >= now - window_ms`.
- Different keys must be tracked independently — recording `"user:a"` must not
  affect `"user:b"`.

Internal design and cleanup requirements:
- The GenServer state must store per-key bucket counts under `state.keys`.
- Memory must not leak: run a periodic cleanup (via `Process.send_after`) that
  removes buckets — and whole keys — that start before `now - window_ms`. Also
  handle a `:cleanup` message sent directly to the process so tests can trigger
  cleanup synchronously. After cleanup, `state.keys` must be an empty map when
  all data has expired.

Give me the complete module in a single file. Use only the OTP standard library,
no external dependencies.