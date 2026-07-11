Write me an Elixir GenServer module called `RollupTSDB` that implements a time-series storage engine that **pre-aggregates data on ingest** instead of keeping raw samples. Rather than storing every data point, each series keeps one compact *rollup accumulator* per fixed-width time bucket, so memory use per bucket is constant no matter how many points land in it.

## Public API

- `RollupTSDB.start_link(opts)` to start the process. It should accept:
  - `:bucket_duration_ms` — the width of each rollup bucket in milliseconds (default `60_000`, i.e. one minute). Every unique series (metric name + exact label set) gets one rollup accumulator per time bucket.
  - `:clock` — a zero-arity function returning the current time in milliseconds. Default to `fn -> System.monotonic_time(:millisecond) end`.
  - `:name` — optional process registration name.
  - `:retention_ms` — how long to keep buckets before they are eligible for cleanup (default `3_600_000`, i.e. one hour).
  - `:cleanup_interval_ms` — how often to run automatic cleanup of expired buckets via `Process.send_after` (default `60_000`). Accept `:infinity` to disable.

- `RollupTSDB.insert(server, metric_name, labels, timestamp, value)` where:
  - `metric_name` is a string like `"http_requests_total"`.
  - `labels` is a map like `%{"method" => "GET", "status" => "200"}`.
  - `timestamp` is an integer in milliseconds.
  - `value` is a number (integer or float).
  - The function should return `:ok`.
  - The point is folded into the rollup accumulator for the bucket identified by `bucket_start = div(timestamp, bucket_duration_ms) * bucket_duration_ms`. A series is identified by the tuple `{metric_name, sorted_labels}`, where `sorted_labels = Enum.sort(Map.to_list(labels))`, so label ordering never creates duplicate series.
  - **No raw points are stored.** Each bucket's accumulator is updated in place as follows (the first point to arrive in a bucket seeds the accumulator; each later point folds in):
    - `count` — number of points folded in so far.
    - `sum` — running sum of values.
    - `min` — smallest value seen.
    - `max` — largest value seen.
    - `first` — the value of the point with the **smallest timestamp** folded into the bucket. On a tie for the smallest timestamp, the earliest-arriving point wins (i.e. only replace `first` when a strictly smaller timestamp arrives).
    - `last` — the value of the point with the **largest timestamp** folded into the bucket. On a tie for the largest timestamp, the latest-arriving point wins (i.e. replace `last` whenever a timestamp greater than or equal to the current largest arrives).

- `RollupTSDB.query(server, metric_name, label_matchers, {start_ts, end_ts})` where:
  - `label_matchers` is a map of label key-value pairs. A series matches if it contains **all** of the specified key-value pairs (it may have additional labels). An empty map `%{}` matches all series with that metric name.
  - The return value is a list of `{labels, buckets}` tuples, where `labels` is the full label map for that series and `buckets` is a list of `{bucket_start, stats}` tuples, sorted ascending by `bucket_start`, and restricted to buckets whose `bucket_start` satisfies `start_ts <= bucket_start <= end_ts`.
  - `stats` is a map with exactly these keys:
    - `:count`, `:sum`, `:min`, `:max` — as accumulated above.
    - `:avg` — `sum / count` (a float).
    - `:first`, `:last` — as accumulated above.
  - A series that matches but which has NO bucket in the `[start_ts, end_ts]` range must be omitted from the result entirely — never returned as a `{labels, []}` tuple. When no matched series has any bucket in range, the result is `[]`.

## Cleanup

Handle a `:cleanup` info message that removes any bucket whose `bucket_start + bucket_duration_ms` is less than or equal to `now - retention_ms` (where `now` comes from `:clock`). A series left with zero buckets after cleanup is removed entirely. Also schedule this periodically using `Process.send_after` based on `:cleanup_interval_ms`.

## Constraints

- Use only OTP standard library — no external dependencies.
- Give me the complete module in a single file.
- All operations go through the GenServer (`call`/`cast`) — no ETS, no separate processes.