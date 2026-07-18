Write me an Elixir module called `TimeSeriesResampler` that takes a list of `{timestamp, value}` tuples at irregular intervals and resamples them into fixed-interval buckets.

I need these functions in the public API:

- `TimeSeriesResampler.resample(data, interval_ms, opts)` — the main entry point. `data` is a list of `{timestamp_ms, value}` tuples (integers and numbers). `interval_ms` is the bucket width in milliseconds. `opts` is a keyword list. Returns a list of `{bucket_start_ms, aggregated_value}` tuples sorted ascending by bucket start.

The options are:
- `:agg` — the aggregation mode, one of `:last`, `:first`, `:mean`, `:sum`, `:count`, `:max`, `:min`. Defaults to `:last`.
- `:fill` — how to handle buckets with no data points. Either `:nil` (emit `{bucket_start, nil}`) or `:forward` (carry the last known aggregated value forward). Defaults to `:nil`.

Bucketing rules:
- The first bucket starts at the timestamp of the earliest data point, floored to the nearest `interval_ms` boundary (i.e. `floor(min_ts / interval_ms) * interval_ms`).
- The last bucket is the one that contains the latest data point.
- Every bucket between first and last must appear in the output, even if empty.
- A data point at timestamp `t` belongs to the bucket with start `floor(t / interval_ms) * interval_ms`.
- Here `floor` is the true mathematical floor (round toward negative infinity), not truncation toward zero. Timestamps may be negative, so a point at `t = -100` with `interval_ms = 2000` falls in the bucket starting at `-2000` (not `0`), and a point at `t = -3000` falls in the bucket starting at `-4000`. A point landing exactly on a boundary (e.g. `t = 2000`) belongs to the bucket that starts there, not the one before it.

Aggregation rules per mode:
- `:last` — the value of the latest timestamp in the bucket.
- `:first` — the value of the earliest timestamp in the bucket.
- `:mean` — arithmetic mean of all values in the bucket, always returned as a float (e.g. two integer values `10` and `20` yield `15.0`, not `15`).
- `:sum` — sum of all values.
- `:count` — number of data points in the bucket (integer).
- `:max` — maximum value.
- `:min` — minimum value.

Gap filling:
- `:nil` — empty buckets get `nil` as their value.
- `:forward` — empty buckets get the aggregated value of the most recent non-empty bucket to their left (this applies to every aggregation mode, including `:count`). If there is no such bucket (gap at the very start), use `nil`.

Edge cases to handle:
- Empty input list → return `[]`.
- Single data point → return a single bucket.
- All points in the same bucket → return one bucket.
- Input may be given in any order; sort internally before processing.

Give me the complete module in a single file. Use only the Elixir standard library, no external dependencies.
