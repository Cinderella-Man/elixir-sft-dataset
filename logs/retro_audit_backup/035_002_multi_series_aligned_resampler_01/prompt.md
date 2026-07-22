Write me an Elixir module called `MultiSeriesResampler` that takes **several named time
series** — each a list of `{timestamp, value}` tuples at irregular intervals — and
resamples them onto a **single shared fixed-interval grid**, aligning every series so that
each output row carries one aggregated value per series.

I need this public API:

- `MultiSeriesResampler.resample(series, interval_ms, opts)` — the main entry point.
  `series` is a map of `%{series_name => [{timestamp_ms, value}]}` (names are any term,
  usually atoms; timestamps are integers, values are numbers). `interval_ms` is the bucket
  width in milliseconds. `opts` is a keyword list. Returns a list of
  `{bucket_start_ms, %{series_name => aggregated_value}}` tuples sorted ascending by bucket
  start. **Every series name present in the input map appears in every row's value map**,
  even if that series has no data in that bucket.

The options are:
- `:agg` — the aggregation mode applied to every series, one of `:last`, `:first`, `:mean`,
  `:sum`, `:count`, `:max`, `:min`. Defaults to `:last`.
- `:fill` — how to handle, **per series**, buckets with no data points for that series.
  Either `:nil` (put `nil` for that series in that row) or `:forward` (carry that series'
  most recent aggregated value forward). Defaults to `:nil`.

Bucketing rules:
- The grid spans **all** series jointly. The first bucket starts at the earliest timestamp
  across all series, floored to the nearest `interval_ms` boundary
  (`floor(min_ts / interval_ms) * interval_ms`). The last bucket is the one containing the
  latest timestamp across all series.
- Every bucket between first and last must appear in the output, even if all series are
  empty there.
- A data point at timestamp `t` belongs to the bucket with start
  `floor(t / interval_ms) * interval_ms`.

Aggregation is computed **independently per series** within each bucket, using the same
rules as a single-series resampler:
- `:last` / `:first` — value at the latest / earliest timestamp in the bucket for that series.
- `:mean` — arithmetic mean of that series' values in the bucket (float).
- `:sum` — sum of that series' values.
- `:count` — number of that series' points in the bucket (integer).
- `:max` / `:min` — max / min of that series' values.

Gap filling is **per series**:
- `:nil` — a series with no points in a bucket gets `nil` for that bucket.
- `:forward` — a series with no points in a bucket gets its own most recent non-empty
  aggregated value. If that series has had no value yet (leading gap), use `nil`.

Edge cases to handle:
- Empty input map, or a map whose series are all empty lists → return `[]`.
- A series that is present but empty contributes no timestamps to the grid, yet still
  appears (as `nil` / forward-filled) in every row.
- Input for any series may be in any order; sort internally before processing.

Give me the complete module in a single file. Use only the Elixir standard library, no
external dependencies.

## Additional interface contract

- `resample/3` validates its arguments: an `interval_ms` that is not a positive integer
  (e.g. `0`), or an `:agg`/`:fill` option value outside the documented sets (e.g.
  `agg: :median` or `fill: :backward`), raises an `ArgumentError`.