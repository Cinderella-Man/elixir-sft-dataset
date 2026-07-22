Write me an Elixir module called `StreamingResampler` — a **GenServer** that performs
**online, streaming** resampling of a `{timestamp, value}` point stream into fixed-interval
buckets. Unlike a batch resampler, it never sees the whole data set at once: points are
pushed one at a time, and buckets are **finalized (emitted) as an event-time watermark
advances**, with support for bounded late-arriving data.

I need this public API:

- `StreamingResampler.start_link(interval_ms, opts)` — start the server. `interval_ms` is
  the bucket width in milliseconds. Returns `{:ok, pid}`. Raises `ArgumentError` for an
  invalid `interval_ms` or invalid options.
- `StreamingResampler.push(pid, timestamp_ms, value)` — ingest one data point. Returns `:ok`.
  The **watermark** is the maximum timestamp ever seen. Pushing advances the watermark and
  may finalize buckets.
- `StreamingResampler.finalized(pid)` — return the list of buckets finalized *so far*, as
  `{bucket_start_ms, aggregated_value}` tuples sorted ascending by bucket start.
- `StreamingResampler.flush(pid)` — force-finalize every still-open bucket up to and
  including the bucket containing the current watermark, then return the full sorted list of
  all finalized buckets.
- `StreamingResampler.stats(pid)` — return a map with at least `:late_dropped` (count of
  dropped late points), `:watermark`, and `:open_buckets` (number of not-yet-finalized
  buckets currently buffered).

The options are:
- `:agg` — aggregation mode, one of `:last`, `:first`, `:mean`, `:sum`, `:count`, `:max`,
  `:min`. Defaults to `:last`.
- `:fill` — gap-filling for empty buckets that get finalized: `:nil` or `:forward`. Defaults
  to `:nil`.
- `:allowed_lateness` — a non-negative integer number of milliseconds. Defaults to `0`.

Semantics:
- A point at timestamp `t` belongs to the bucket with start
  `floor(t / interval_ms) * interval_ms`.
- The grid's first bucket is fixed by the **first point ever pushed** (floored to a
  boundary). Emission proceeds contiguously from there — every grid bucket is finalized in
  ascending order with no gaps, including empty ones (subject to `:fill`).
- A bucket `[start, start + interval_ms)` is finalized once
  `watermark >= start + interval_ms + allowed_lateness`. Finalizing empty buckets uses the
  `:fill` policy (`:forward` carries the last finalized non-nil aggregate; a leading gap is
  `nil`).
- A point whose bucket has **already been finalized** (its bucket start is earlier than the
  next bucket awaiting emission) is a *late drop*: it is discarded and counted in
  `:late_dropped`. Late points that still fall inside an open bucket (thanks to
  `:allowed_lateness`) are accepted and included in that bucket's aggregate.
- Aggregation follows the usual rules: `:last`/`:first` by timestamp within the bucket
  (points may arrive out of order — order by timestamp internally), `:mean` (float), `:sum`,
  `:count` (integer), `:max`, `:min`.

Edge cases:
- `finalized/1` and `flush/1` before any push return `[]`; `stats/1` reports a `nil`
  watermark.
- After `flush/1`, any subsequently pushed point belonging to an already-emitted bucket is a
  late drop.

Give me the complete module in a single file. Use only the Elixir standard library (GenServer
is fine), no external dependencies.