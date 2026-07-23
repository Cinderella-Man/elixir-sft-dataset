**TSDB — chunked in-memory time-series storage engine (Elixir GenServer)**

Implement a GenServer module `TSDB` providing a metrics-optimized time-series store using a chunked in-memory storage format.

**Startup — `TSDB.start_link(opts)`**
- `opts` is a keyword list; returns `{:ok, pid}` on success.
- `:chunk_duration_ms` — duration of each storage chunk in milliseconds; default `60_000` (one minute). Every unique series (metric name + exact label set) gets one chunk per time window.
- `:clock` — zero-arity function returning current time in milliseconds; default `fn -> System.monotonic_time(:millisecond) end`.
- `:name` — optional process registration name. When absent, the process must still start unnamed; do not pass `name: nil` through to `GenServer.start_link/3`.
- `:retention_ms` — how long chunks are kept before becoming eligible for cleanup; default `3_600_000` (one hour).
- `:cleanup_interval_ms` — how often automatic cleanup of expired chunks runs via `Process.send_after`; default `60_000`. `:infinity` must be accepted and disables scheduling entirely.

**Ingest — `TSDB.insert(server, metric_name, labels, timestamp, value)`**
- `metric_name`: string, e.g. `"http_requests_total"`.
- `labels`: map, e.g. `%{"method" => "GET", "status" => "200"}`; may be empty (`%{}`).
- `timestamp`: integer milliseconds.
- `value`: number (integer or float). Store and return values exactly as given — never coerce between integer and float.
- Returns `:ok`.
- Routes the data point into the correct chunk from `timestamp` and `chunk_duration_ms`. A chunk is identified by `{metric_name, sorted_labels, chunk_start}` with `chunk_start = div(timestamp, chunk_duration_ms) * chunk_duration_ms` — so with `chunk_duration_ms = 1_000`, `t = 1000` belongs to chunk `1000`, not chunk `0`.
- Within each chunk, data points are stored sorted by timestamp.

**Raw read — `TSDB.query(server, metric_name, label_matchers, {start_ts, end_ts})`**
- `label_matchers`: map of label key-value pairs. A series matches when it contains **all** specified key-value pairs; extra labels are allowed. An empty map `%{}` matches all series with that metric name.
- Returns a list of `{labels, points}` tuples. `labels` is the series' full label map (e.g. `%{"host" => "a"}`, or `%{}` for a series inserted with empty labels). `points` is a list of `{timestamp, value}` tuples sorted ascending by timestamp, filtered to `start_ts <= timestamp <= end_ts` (both bounds inclusive).

**Aggregated read — `TSDB.query_agg(server, metric_name, label_matchers, {start_ts, end_ts}, aggregation, step_ms)`**
- `aggregation` is one of `:avg`, `:sum`, `:max`, `:rate`. `step_ms` is the width of each aggregation window.
- Divide `[start_ts, end_ts)` into non-overlapping windows of `step_ms` milliseconds: `[start_ts, start_ts + step_ms)`, `[start_ts + step_ms, start_ts + 2*step_ms)`, etc. A point falls in a window when `window_start <= timestamp < window_start + step_ms`.
- Per matched series, per window, aggregate over the data points whose timestamps land in that window:
  - `:avg` — arithmetic mean of values, a float. Window with no points is omitted from the output.
  - `:sum` — sum of values with no numeric coercion: summing integers yields an integer (`10 + 20 + 30` is `60`, not `60.0`). Window with no points is omitted.
  - `:max` — maximum value returned as stored (integer stays integer). Window with no points is omitted.
  - `:rate` — per-second rate of change as a float, computed as `(last_value - first_value) / ((last_timestamp - first_timestamp) / 1000)`. Window with fewer than 2 points is omitted.
- Return shape matches `query/4`: a list of `{labels, agg_points}` tuples, `agg_points` being `{window_start_timestamp, aggregated_value}` tuples sorted by time. A matched series whose windows are all omitted is itself dropped from the result; when nothing matches, the result is `[]`.

**Storage layout**
- Nested map keyed by `{metric_name, sorted_labels}` (the "series key"); each series key maps to a map of `chunk_start => [sorted data points]`.
- Produce sorted labels by converting the labels map to a sorted keyword-style list (e.g. `Enum.sort(Map.to_list(labels))`) so label ordering never creates duplicate series — inserting with `%{"a" => "1", "b" => "2"}` and with `%{"b" => "2", "a" => "1"}` must land in one and the same series.

**Cleanup**
- Handle a `:cleanup` info message, delivered both by the periodic timer and directly via `send(pid, :cleanup)`.
- Remove any chunk where `chunk_start + chunk_duration_ms <= now - retention_ms`, with `now` from the configured `:clock`.
- A series left with no chunks is removed entirely and no longer appears in any `query/4` or `query_agg/6` result.
- Schedule cleanup periodically with `Process.send_after` based on `:cleanup_interval_ms`.

**Constraints**
- OTP standard library only — no external dependencies.
- Complete module delivered in a single file.
- All operations go through the GenServer (`call`/`cast`) — no ETS, no separate processes.

**Interface contract — empty results**
- In `query/4`, a series whose labels match but which has NO data points inside `[start_ts, end_ts]` is omitted from the result entirely — never returned as a `{labels, []}` tuple with an empty points list.
- When no matched series has any point in range, and when the metric name is unknown, the result is `[]`.
