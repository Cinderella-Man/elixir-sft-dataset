Write me an Elixir module called `ShardedTSDB` that implements a time-series storage engine whose data is **horizontally sharded across several worker processes**. A single coordinator GenServer owns a fixed set of shard GenServers; each series lives on exactly one shard, writes route to the owning shard, and reads fan out across all shards and merge.

## Architecture

- Starting the engine starts one coordinator process plus `:shards` independent worker (shard) GenServers. `start_link/1` returns the coordinator; all public functions take the coordinator as their `server` argument.
- A series is identified by `{metric_name, sorted_labels}` where `sorted_labels = Enum.sort(Map.to_list(labels))`, so label ordering never creates duplicate series.
- The shard index that owns a series is `:erlang.phash2({metric_name, sorted_labels}, shard_count)`, a 0-based integer in `0..(shard_count - 1)`.
- Each shard stores its own series independently using the layout: series key → `%{chunk_start => sorted data points}`, with `chunk_start = div(timestamp, chunk_duration_ms) * chunk_duration_ms`, and points within a chunk kept sorted by timestamp.

## Public API

- `ShardedTSDB.start_link(opts)` accepting:
  - `:shards` — the number of shard worker processes to start (default `4`).
  - `:chunk_duration_ms` — chunk width in milliseconds (default `60_000`).
  - `:clock` — a zero-arity function returning the current time in milliseconds. Default to `fn -> System.monotonic_time(:millisecond) end`.
  - `:name` — optional registration name for the coordinator.
  - `:retention_ms` — how long to keep chunks before cleanup (default `3_600_000`).
  - `:cleanup_interval_ms` — how often the coordinator triggers cleanup across all shards via `Process.send_after` (default `60_000`). Accept `:infinity` to disable.

- `ShardedTSDB.insert(server, metric_name, labels, timestamp, value)` — routes the point to the owning shard and returns `:ok`.

- `ShardedTSDB.query(server, metric_name, label_matchers, {start_ts, end_ts})` — fans out to all shards and merges results. `label_matchers` is a map; a series matches if it contains **all** the specified key-value pairs (it may have more). `%{}` matches all series with that metric name. Returns a list of `{labels, points}` tuples, where `points` is the `{timestamp, value}` list for that series sorted ascending by timestamp and filtered to `start_ts <= timestamp <= end_ts`. A matched series with no point in range is omitted entirely; when nothing matches, the result is `[]`. The order of series in the merged list is unspecified.

- `ShardedTSDB.query_agg(server, metric_name, label_matchers, {start_ts, end_ts}, aggregation, step_ms)` where:
  - `aggregation` is one of `:sum`, `:avg`, `:max`.
  - `step_ms` is the window width. The range `[start_ts, end_ts)` is divided into non-overlapping windows `[start_ts, start_ts + step_ms)`, `[start_ts + step_ms, start_ts + 2*step_ms)`, etc.
  - For each matched series and each window, take the points whose timestamps fall in `[window_start, window_start + step_ms)` and compute:
    - `:sum` — the sum of values; omit the window if it has no points.
    - `:avg` — the arithmetic mean of values; omit the window if it has no points.
    - `:max` — the maximum value; omit the window if it has no points.
  - Returns a list of `{labels, agg_points}` tuples, where `agg_points` is a list of `{window_start, aggregated_value}` tuples sorted by window start. A matched series whose windows are all omitted is left out of the result.

## Introspection helpers

- `ShardedTSDB.shard_count(server)` — returns the configured number of shards.
- `ShardedTSDB.shard_of(server, metric_name, labels)` — returns the 0-based shard index that owns the given series, i.e. `:erlang.phash2({metric_name, Enum.sort(Map.to_list(labels))}, shard_count)`.
- `ShardedTSDB.series_count(server)` — returns the total number of distinct series stored across all shards.
- `ShardedTSDB.cleanup(server)` — synchronously runs cleanup across all shards and returns `:ok`. Cleanup removes any chunk whose `chunk_start + chunk_duration_ms` is less than or equal to `now - retention_ms` (where `now` comes from `:clock`), and drops any series left with zero chunks.

## Cleanup

In addition to the `cleanup/1` function, the coordinator schedules cleanup periodically with `Process.send_after` based on `:cleanup_interval_ms` and applies the same rule across all shards.

## Constraints

- Use only OTP standard library — no external dependencies.
- Give me the complete module in a single file.
- No ETS — all storage lives in the shard processes' GenServer state.