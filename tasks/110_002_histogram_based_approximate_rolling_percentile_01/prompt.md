# Histogram-Based Approximate Rolling Percentile

Write me an Elixir GenServer module called `HistogramPercentile` that estimates
percentiles over a rolling time window using a **fixed bucket histogram** instead
of storing every raw sample. A single running process manages many independent
**series**, each identified by an arbitrary `name` term.

Unlike a sorted-list calculator, this variant trades exactness for **bounded
memory**: no matter how many samples arrive, a series only ever stores a small
grid of per-time-slice bucket counts.

## Public API

- `HistogramPercentile.start_link(opts)` — starts and registers the process.
  Supported options:
  - `:name` — the name to register under. Default: `HistogramPercentile`.
  - `:clock` — a zero-arity function returning the current time in milliseconds.
    Default: `fn -> System.monotonic_time(:millisecond) end`. Every timestamp used
    for windowing must come from this function.
  - `:edges` — **required**. A strictly increasing list of at least two numbers
    `[e0, e1, …, ek]` defining `k` buckets. Bucket `i` covers `[e_i, e_{i+1})`,
    with the final bucket `[e_{k-1}, ek]` treated as closed. A recorded value below
    `e0` is clamped into bucket 0; a value at or above `ek` is clamped into the last
    bucket. Supplying anything else raises `ArgumentError`.
  - `:window_ms` — **required** positive integer. A sample recorded at time `t`
    contributes to queries while `now - t < window_ms`.
  - `:slots` — positive integer, default `60`. The window is divided into this many
    time slices; each series keeps one histogram per slice in a ring buffer. When a
    slice's slot is reused in a later cycle, its old counts are discarded.

- `HistogramPercentile.record(name, value)` — increments the bucket for `value`
  in the current time slice of series `name`. Returns `:ok`.

- `HistogramPercentile.query(name, percentile)` — returns `{:ok, estimate}` where
  `estimate` is a float, or `{:error, :empty}` when no live counts exist.
  `percentile` is a float in `0.0..1.0`.

- `HistogramPercentile.reset(name)` — discards all counts for series `name`.
  Returns `:ok`.

## Estimation algorithm (histogram quantile)

At query time, sum the per-bucket counts across every stored slice whose start
time `s` satisfies `now - s < window_ms`, producing a list of counts
`c_0 … c_{k-1}` with total `n`. If `n == 0`, return `{:error, :empty}`. Otherwise
use Prometheus-style linear interpolation:

```
target = percentile * n
walk buckets in order, tracking cum_before (counts in earlier buckets);
pick the first bucket i where cum_before + c_i >= target (or the last bucket);
lo = e_i,  hi = e_{i+1},  frac = (target - cum_before) / c_i  (0 if c_i == 0)
estimate = lo + (hi - lo) * clamp(frac, 0.0, 1.0)
```

Consequences:
- `percentile = 0.0` returns `e0` (the low edge).
- `percentile = 1.0` returns `ek` (the high edge).
- Results are approximate; error is bounded by bucket width.

## Semantics

- Series are fully independent.
- Windowing is applied at query time, so advancing the clock and re-querying
  reflects newly-expired slices.

## Constraints

Give me the complete module in a single file. Use only the OTP standard library —
no external dependencies.