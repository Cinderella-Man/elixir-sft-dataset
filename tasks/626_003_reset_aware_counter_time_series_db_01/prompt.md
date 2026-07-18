Write me an Elixir GenServer module called `CounterTSDB` that implements a time-series storage engine specialized for **monotonic counters** (values that normally only increase, like `http_requests_total`). Unlike a plain gauge store, its range queries must be **reset-aware**: when a counter is observed to drop, that drop is interpreted as a counter reset (the process restarted and the counter went back toward zero), not as a negative change.

## Public API

- `CounterTSDB.start_link(opts)` to start the process, returning `{:ok, pid}`. It should accept:
  - `:chunk_duration_ms` — the duration of each storage chunk in milliseconds (default `60_000`). Every unique series (metric name + exact label set) gets one chunk per time window.
  - `:clock` — a zero-arity function returning the current time in milliseconds. Default to `fn -> System.monotonic_time(:millisecond) end`.
  - `:name` — optional process registration name; when given, the process registers under it so every public API function can be called with that name in place of the pid.
  - `:retention_ms` — how long to keep chunks before they are eligible for cleanup (default `3_600_000`).
  - `:cleanup_interval_ms` — how often to run automatic cleanup of expired chunks via `Process.send_after` (default `60_000`). Accept `:infinity` to disable.

- `CounterTSDB.insert(server, metric_name, labels, timestamp, value)` where:
  - `metric_name` is a string; `labels` is a map like `%{"instance" => "a"}`; `timestamp` is an integer in milliseconds; `value` is a number.
  - The function should return `:ok`.
  - The point is stored into the chunk identified by `chunk_start = div(timestamp, chunk_duration_ms) * chunk_duration_ms`. A series is identified by `{metric_name, sorted_labels}` where `sorted_labels = Enum.sort(Map.to_list(labels))`, so label ordering never creates duplicate series. Within each chunk, data points must be stored sorted by timestamp. Two points may share the same timestamp; both are kept.

- `CounterTSDB.query(server, metric_name, label_matchers, {start_ts, end_ts})` returns raw samples:
  - `label_matchers` is a map; a series matches if it contains **all** the specified key-value pairs (it may have additional labels). An empty map `%{}` matches all series with that metric name.
  - Returns a list of `{labels, points}` tuples, where `labels` is the series' label map as inserted (a map, not the sorted list used as the internal key) and `points` is the list of `{timestamp, value}` tuples for that series sorted ascending by timestamp and filtered to `start_ts <= timestamp <= end_ts`.
  - A series that matches but has NO point in `[start_ts, end_ts]` must be omitted entirely — never returned as `{labels, []}`. When nothing matches — no such metric name, or no series satisfying the matchers — the result is `[]`.

- `CounterTSDB.query_range(server, metric_name, label_matchers, {start_ts, end_ts}, function, step_ms)` where:
  - `function` is one of `:increase` or `:rate`.
  - `step_ms` is the width of each window.
  - The time range `[start_ts, end_ts)` is divided into non-overlapping windows of `step_ms` milliseconds: `[start_ts, start_ts + step_ms)`, `[start_ts + step_ms, start_ts + 2*step_ms)`, etc.
  - For each matched series and each window, take the points whose timestamps fall in `[window_start, window_start + step_ms)`, sorted ascending by timestamp. Then:
    - `:increase` — the total increase across the window, computed reset-aware. Walk consecutive point pairs `(prev_value, cur_value)` in timestamp order; for each pair the contributed delta is `cur_value - prev_value` when `cur_value >= prev_value` (so two equal consecutive values contribute `0`, not a reset), otherwise (a reset is detected) the contributed delta is `cur_value` (treat it as having climbed from zero to `cur_value`). The window's increase is the sum of these deltas, computed with plain arithmetic so integer samples yield an integer increase. If the window has fewer than 2 points, the window is omitted.
    - `:rate` — the reset-aware increase (computed exactly as above) divided by the elapsed seconds across the window: `increase / ((last_timestamp - first_timestamp) / 1000)`, where `first_timestamp`/`last_timestamp` are the smallest and largest timestamps of the points in that window. If the window has fewer than 2 points, or if `last_timestamp == first_timestamp`, the window is omitted (other windows of the same series still appear).
  - The return value is a list of `{labels, range_points}` tuples, where `labels` is the series' label map and `range_points` is a list of `{window_start, computed_value}` tuples sorted by window start. A matched series whose windows are all omitted is left out of the result entirely, so when nothing survives the result is `[]`.

## Cleanup

Handle a `:cleanup` info message that removes any chunk whose `chunk_start + chunk_duration_ms` is less than or equal to `now - retention_ms` (where `now` comes from `:clock`). A series left with zero chunks is removed entirely. Also schedule this periodically using `Process.send_after` based on `:cleanup_interval_ms`: schedule the first pass at startup and schedule the next one after each pass runs, so cleanup keeps repeating on its own without anything sending `:cleanup`. Only cleanup consults `:clock`.

## Constraints

- Use only OTP standard library — no external dependencies.
- Give me the complete module in a single file.
- All operations go through the GenServer (`call`/`cast`) — no ETS, no separate processes.
