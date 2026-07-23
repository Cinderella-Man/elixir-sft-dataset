# Design brief: `RollupTSDB` — a pre-aggregating time-series store

## Problem

A conventional time-series store keeps every raw sample it is handed, so the memory
cost of a hot series grows without bound as points arrive. We want the opposite
trade-off: an Elixir GenServer module called `RollupTSDB` that implements a
time-series storage engine which **pre-aggregates data on ingest** instead of
keeping raw samples. Rather than storing every data point, each series keeps one
compact *rollup accumulator* per fixed-width time bucket, so memory use per bucket
is constant no matter how many points land in it.

## Constraints on the solution

- Use only OTP standard library — no external dependencies.
- Deliver the complete module in a single file.
- All operations go through the GenServer (`call`/`cast`) — no ETS, no separate
  processes.
- The `:clock` function is consulted **only when a cleanup run happens** — never
  during `init`, `insert`, or `query`.
- **No raw points are stored.**

## Required interface

1. **`RollupTSDB.start_link(opts)`** — starts the process, returning `{:ok, pid}`.
   It should accept these options:
   1.1. `:bucket_duration_ms` — the width of each rollup bucket in milliseconds
   (default `60_000`, i.e. one minute). Every unique series (metric name + exact
   label set) gets one rollup accumulator per time bucket.
   1.2. `:clock` — a zero-arity function returning the current time in
   milliseconds. Default to `fn -> System.monotonic_time(:millisecond) end`.
   1.3. `:name` — optional process registration name. When omitted, the process is
   started unregistered.
   1.4. `:retention_ms` — how long to keep buckets before they are eligible for
   cleanup (default `3_600_000`, i.e. one hour).
   1.5. `:cleanup_interval_ms` — how often to run automatic cleanup of expired
   buckets via `Process.send_after` (default `60_000`). Accept `:infinity` to
   disable.

2. **`RollupTSDB.insert(server, metric_name, labels, timestamp, value)`** — folds
   one point into the store, where:
   2.1. `metric_name` is a string like `"http_requests_total"`.
   2.2. `labels` is a map like `%{"method" => "GET", "status" => "200"}`.
   2.3. `timestamp` is an integer in milliseconds.
   2.4. `value` is a number (integer or float).
   2.5. The function should return `:ok`.
   2.6. The point is folded into the rollup accumulator for the bucket identified by
   `bucket_start = div(timestamp, bucket_duration_ms) * bucket_duration_ms`.
   2.7. A series is identified by the tuple `{metric_name, sorted_labels}`, where
   `sorted_labels = Enum.sort(Map.to_list(labels))`, so label ordering never creates
   duplicate series.

3. **The bucket accumulator** — each bucket's accumulator is updated in place as
   follows (the first point to arrive in a bucket seeds the accumulator; each later
   point folds in):
   3.1. `count` — number of points folded in so far.
   3.2. `sum` — running sum of values.
   3.3. `min` — smallest value seen.
   3.4. `max` — largest value seen.
   3.5. `first` — the value of the point with the **smallest timestamp** folded into
   the bucket. On a tie for the smallest timestamp, the earliest-arriving point wins
   (i.e. only replace `first` when a strictly smaller timestamp arrives).
   3.6. `last` — the value of the point with the **largest timestamp** folded into
   the bucket. On a tie for the largest timestamp, the latest-arriving point wins
   (i.e. replace `last` whenever a timestamp greater than or equal to the current
   largest arrives).

4. **`RollupTSDB.query(server, metric_name, label_matchers, {start_ts, end_ts})`** —
   reads rollups back out, where:
   4.1. `label_matchers` is a map of label key-value pairs. A series matches if it
   contains **all** of the specified key-value pairs (it may have additional
   labels). An empty map `%{}` matches all series with that metric name.
   4.2. The return value is a list of `{labels, buckets}` tuples, where `labels` is
   the full label map for that series and `buckets` is a list of
   `{bucket_start, stats}` tuples, sorted ascending by `bucket_start`, and
   restricted to buckets whose `bucket_start` satisfies
   `start_ts <= bucket_start <= end_ts`.
   4.3. `stats` is a map with exactly these keys and no others: `:count`, `:sum`,
   `:min`, `:max` — as accumulated above; `:avg` — `sum / count` (always a float);
   `:first`, `:last` — as accumulated above.

5. **Cleanup on the `:cleanup` info message** — handle a `:cleanup` info message
   that removes any bucket whose `bucket_start + bucket_duration_ms` is less than or
   equal to `now - retention_ms` (where `now` comes from `:clock`).
   5.1. A series left with zero buckets after cleanup is removed entirely.
   5.2. This message may also be sent directly to the process (`send(db, :cleanup)`)
   to force a cleanup run.
   5.3. Any other info message must be ignored without crashing.

6. **Periodic scheduling** — also schedule this periodically using
   `Process.send_after`: arm the first timer during `init` using
   `:cleanup_interval_ms`, and re-arm it after each `:cleanup` run so automatic
   cleanup keeps repeating. When `:cleanup_interval_ms` is `:infinity`, no timer is
   armed at all and no automatic cleanup ever runs.

## Acceptance criteria

- Memory per bucket stays constant regardless of how many points are folded into
  it, because only the accumulator fields above are retained.
- Two inserts whose `labels` maps differ only in ordering land in the same series.
- `insert/5` returns `:ok`.
- `start_link/1` returns `{:ok, pid}`, and the process is unregistered when `:name`
  is omitted.
- Tie-breaking on `first` and `last` behaves exactly as specified in 3.5 and 3.6.
- `:avg` is always a float.
- A series that matches but which has NO bucket in the `[start_ts, end_ts]` range
  must be omitted from the result entirely — never returned as a `{labels, []}`
  tuple. When no matched series has any bucket in range (including when the metric
  name is unknown), the result is `[]`.
- No call to the `:clock` function occurs during `init`, `insert`, or `query`.
- Sending an unrelated info message does not crash the process.
- The deliverable is one self-contained file, OTP-only, with all state held in the
  GenServer.
