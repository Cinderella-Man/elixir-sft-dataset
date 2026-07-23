# `CounterTSDB` — Reset-Aware Counter Time-Series Store

## Overview

This document specifies an Elixir GenServer module named `CounterTSDB`: a time-series storage engine specialized for **monotonic counters** — values that normally only increase, such as `http_requests_total`.

Unlike a plain gauge store, its range queries are **reset-aware**: when a counter is observed to drop, that drop is interpreted as a counter reset (the process restarted and the counter went back toward zero), not as a negative change.

## Public API

### `CounterTSDB.start_link(opts)`

Starts the process, returning `{:ok, pid}`. The following options are accepted:

- `:chunk_duration_ms` — the duration of each storage chunk in milliseconds (default `60_000`). Every unique series (metric name + exact label set) gets one chunk per time window.
- `:clock` — a zero-arity function returning the current time in milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
- `:name` — optional process registration name; when given, the process registers under it so every public API function can be called with that name in place of the pid.
- `:retention_ms` — how long chunks are kept before they become eligible for cleanup (default `3_600_000`).
- `:cleanup_interval_ms` — how often automatic cleanup of expired chunks runs via `Process.send_after` (default `60_000`). The value `:infinity` is accepted and disables it.

### `CounterTSDB.insert(server, metric_name, labels, timestamp, value)`

- `metric_name` is a string; `labels` is a map like `%{"instance" => "a"}`; `timestamp` is an integer in milliseconds; `value` is a number.
- The function returns `:ok`.
- The point is stored into the chunk identified by `chunk_start = div(timestamp, chunk_duration_ms) * chunk_duration_ms`. A series is identified by `{metric_name, sorted_labels}` where `sorted_labels = Enum.sort(Map.to_list(labels))`, so label ordering never creates duplicate series. Within each chunk, data points are stored sorted by timestamp. Two points may share the same timestamp; both are kept.

### `CounterTSDB.query(server, metric_name, label_matchers, {start_ts, end_ts})`

Returns raw samples.

- `label_matchers` is a map; a series matches if it contains **all** the specified key-value pairs (it may have additional labels). An empty map `%{}` matches all series with that metric name.
- The return value is a list of `{labels, points}` tuples, where `labels` is the series' label map as inserted (a map, not the sorted list used as the internal key) and `points` is the list of `{timestamp, value}` tuples for that series, sorted ascending by timestamp and filtered to `start_ts <= timestamp <= end_ts`.

### `CounterTSDB.query_range(server, metric_name, label_matchers, {start_ts, end_ts}, function, step_ms)`

- `function` is one of `:increase` or `:rate`.
- `step_ms` is the width of each window.
- The time range `[start_ts, end_ts)` is divided into non-overlapping windows of `step_ms` milliseconds: `[start_ts, start_ts + step_ms)`, `[start_ts + step_ms, start_ts + 2*step_ms)`, and so on.
- For each matched series and each window, the points whose timestamps fall in `[window_start, window_start + step_ms)` are taken, sorted ascending by timestamp. Then:
  - `:increase` — the total increase across the window, computed reset-aware. Consecutive point pairs `(prev_value, cur_value)` are walked in timestamp order; for each pair the contributed delta is `cur_value - prev_value` when `cur_value >= prev_value` (so two equal consecutive values contribute `0`, not a reset), otherwise (a reset is detected) the contributed delta is `cur_value` (treated as having climbed from zero to `cur_value`). The window's increase is the sum of these deltas, computed with plain arithmetic so integer samples yield an integer increase.
  - `:rate` — the reset-aware increase (computed exactly as above) divided by the elapsed seconds across the window: `increase / ((last_timestamp - first_timestamp) / 1000)`, where `first_timestamp`/`last_timestamp` are the smallest and largest timestamps of the points in that window.
- The return value is a list of `{labels, range_points}` tuples, where `labels` is the series' label map and `range_points` is a list of `{window_start, computed_value}` tuples sorted by window start.

## Cleanup

The server handles a `:cleanup` info message that removes any chunk whose `chunk_start + chunk_duration_ms` is less than or equal to `now - retention_ms` (where `now` comes from `:clock`). A series left with zero chunks is removed entirely.

This pass is also scheduled periodically using `Process.send_after` based on `:cleanup_interval_ms`: the first pass is scheduled at startup and the next one is scheduled after each pass runs, so cleanup keeps repeating on its own without anything sending `:cleanup`. Only cleanup consults `:clock`.

## Edge cases

- **`query/4`, series with no points in range:** a series that matches but has NO point in `[start_ts, end_ts]` is omitted entirely — it is never returned as `{labels, []}`.
- **`query/4`, nothing matches:** when nothing matches — no such metric name, or no series satisfying the matchers — the result is `[]`.
- **`query_range/6`, `:increase` with sparse windows:** if the window has fewer than 2 points, the window is omitted.
- **`query_range/6`, `:rate` with sparse or zero-span windows:** if the window has fewer than 2 points, or if `last_timestamp == first_timestamp`, the window is omitted (other windows of the same series still appear).
- **`query_range/6`, fully omitted series:** a matched series whose windows are all omitted is left out of the result entirely, so when nothing survives the result is `[]`.
- **Equal consecutive counter values:** these contribute `0` rather than being treated as a reset.
- **Label ordering:** because series keys use `sorted_labels`, differing label ordering never creates duplicate series.
- **Duplicate timestamps:** two points may share the same timestamp; both are kept.

## Constraints

- Only the OTP standard library may be used — no external dependencies.
- The complete module is to be provided in a single file.
- All operations go through the GenServer (`call`/`cast`) — no ETS, no separate processes.
