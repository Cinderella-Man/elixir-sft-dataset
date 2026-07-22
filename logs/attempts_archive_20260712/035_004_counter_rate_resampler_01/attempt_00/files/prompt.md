Write me an Elixir module called `CounterResampler` that resamples a stream of readings from
a **monotonically increasing counter** (think Prometheus-style counters: request totals,
bytes sent, etc.) into fixed-interval buckets of **per-interval increase or rate**, with
**counter-reset detection**. This is different from a plain aggregator: the values are
cumulative, so what matters is the *change* between consecutive samples, not the samples
themselves.

I need this public API:

- `CounterResampler.resample(data, interval_ms, opts)` — the main entry point. `data` is a
  list of `{timestamp_ms, counter_value}` tuples (integers and non-negative numbers) at
  irregular intervals. `interval_ms` is the bucket width in milliseconds. `opts` is a keyword
  list. Returns a list of `{bucket_start_ms, resampled_value}` tuples sorted ascending by
  bucket start.

The options are:
- `:mode` — `:delta` (default) emits the total counter increase attributed to the bucket;
  `:rate` emits that increase divided by the interval length in seconds
  (`interval_ms / 1000`), yielding a float per-second rate.
- `:reset` — `:detect` (default) or `:raw`. Controls how a decrease between two consecutive
  samples is interpreted (see below).
- `:fill` — `:zero` (default) or `:nil`. How to fill buckets that receive no measured
  increase.

Computation rules:
- Sort samples ascending by timestamp first (input may be unordered).
- Increases are computed between **consecutive samples**. For consecutive samples
  `(t0, v0)` then `(t1, v1)`, the increment is:
  - `:reset` = `:detect` → if `v1 >= v0`, the increment is `v1 - v0`; if `v1 < v0`, the
    counter is assumed to have reset, and the increment is taken to be `v1` (the value
    accumulated since the reset).
  - `:reset` = `:raw` → the increment is always `v1 - v0` (may be negative).
- Each consecutive increment is attributed to the bucket of the **later** sample `t1`
  (`floor(t1 / interval_ms) * interval_ms`).
- A bucket's value is the **sum** of all increments attributed to it. Because the very first
  sample has no predecessor, it contributes no increment (a bucket containing only the first
  sample and nothing else has no measured increase).

Bucketing rules:
- The first bucket starts at the earliest sample timestamp, floored to an `interval_ms`
  boundary. The last bucket is the one containing the latest sample. Every bucket in between
  appears in the output.
- For `:delta` mode, a bucket with no attributed increment is `0` under `:fill = :zero` or
  `nil` under `:fill = :nil`. For `:rate` mode, an empty bucket is `0.0` under `:zero` or
  `nil` under `:nil`.

Edge cases:
- Empty input → `[]`.
- A single sample → exactly one bucket whose value is the empty/`fill` value (no predecessor,
  so no measured increase).
- All samples in one bucket → one bucket summing the increments between them.

Give me the complete module in a single file. Use only the Elixir standard library, no
external dependencies.