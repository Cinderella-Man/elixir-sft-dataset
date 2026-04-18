Write me an Elixir GenServer module called `TSDB` that implements a time-series storage engine optimized for metrics, using a chunked in-memory storage format.

## Public API

- `TSDB.start_link(opts)` to start the process. It should accept:
  - `:chunk_duration_ms` — the duration of each storage chunk in milliseconds (default `60_000`, i.e. one minute). Every unique series (metric name + exact label set) gets one chunk per time window.
  - `:clock` — a zero-arity function returning the current time in milliseconds. Default to `fn -> System.monotonic_time(:millisecond) end`.
  - `:name` — optional process registration name.
  - `:retention_ms` — how long to keep chunks before they are eligible for cleanup (default `3_600_000`, i.e. one hour).
  - `:cleanup_interval_ms` — how often to run automatic cleanup of expired chunks via `Process.send_after` (default `60_000`). Accept `:infinity` to disable.

- `TSDB.insert(server, metric_name, labels, timestamp, value)` where:
  - `metric_name` is a string like `"http_requests_total"`.
  - `labels` is a map like `%{"method" => "GET", "status" => "200"}`.
  - `timestamp` is an integer in milliseconds.
  - `value` is a number (integer or float).
  - The function should return `:ok`.
  - Internally, the data point must be placed into the correct chunk based on `timestamp` and `chunk_duration_ms`. A chunk is identified by the tuple `{metric_name, sorted_labels, chunk_start}` where `chunk_start = div(timestamp, chunk_duration_ms) * chunk_duration_ms`. Within each chunk, data points must be stored sorted by timestamp.

- `TSDB.query(server, metric_name, label_matchers, {start_ts, end_ts})` where:
  - `label_matchers` is a map of label key-value pairs. A series matches if it contains **all** of the specified key-value pairs (it may have additional labels). An empty map `%{}` matches all series with that metric name.
  - The return value is a list of `{labels, points}` tuples, where `labels` is the full label map for that series and `points` is a list of `{timestamp, value}` tuples, sorted by timestamp, filtered to `start_ts <= timestamp <= end_ts`.

- `TSDB.query_agg(server, metric_name, label_matchers, {start_ts, end_ts}, aggregation, step_ms)` where:
  - `aggregation` is one of `:avg`, `:sum`, `:max`, `:rate`.
  - `step_ms` is the width of each aggregation window.
  - The function divides the time range `[start_ts, end_ts)` into non-overlapping windows of `step_ms` milliseconds: `[start_ts, start_ts + step_ms)`, `[start_ts + step_ms, start_ts + 2*step_ms)`, etc.
  - For each matched series and each window, compute the aggregation over data points whose timestamps fall within that window:
    - `:avg` — arithmetic mean of values. If the window has no points, the window is omitted from the output.
    - `:sum` — sum of values. If the window has no points, the window is omitted.
    - `:max` — maximum value. If the window has no points, the window is omitted.
    - `:rate` — per-second rate of change. Computed as `(last_value - first_value) / ((last_timestamp - first_timestamp) / 1000)`. If a window has fewer than 2 points, the window is omitted.
  - The return value has the same shape as `query/4`: a list of `{labels, agg_points}` tuples, where `agg_points` is a list of `{window_start_timestamp, aggregated_value}` tuples sorted by time.

## Storage Design

Internally, use a nested map structure keyed by `{metric_name, sorted_labels}` (the "series key"), where each series key maps to a map of `chunk_start => [sorted data points]`. The sorted labels should be produced by converting the labels map to a sorted keyword-style list (e.g. `Enum.sort(Map.to_list(labels))`) so that label ordering doesn't create duplicate series.

## Cleanup

Handle a `:cleanup` info message that removes any chunks whose `chunk_start + chunk_duration_ms` is older than `now - retention_ms`. Also schedule this periodically using `Process.send_after` based on `:cleanup_interval_ms`.

## Constraints

- Use only OTP standard library — no external dependencies.
- Give me the complete module in a single file.
- All operations go through the GenServer (`call`/`cast`) — no ETS, no separate processes.