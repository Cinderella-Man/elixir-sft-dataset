# SLA Percentile Monitor with Inverse Queries

Write me an Elixir GenServer module called `RankPercentile` that maintains rolling
windows of numeric samples and answers questions in **both directions**: given a
percentile, what value? *and* given a value, what percentile / how many samples
exceed it? A single running process manages many independent **series**, each
identified by an arbitrary `name` term.

The inverse queries make this a latency/SLA monitor: `query/2` gives you the pXX
latency, `rank/2` gives you "what fraction of requests came in under X", and
`count_above/2` gives you the raw count of SLA violations.

## Public API

- `RankPercentile.start_link(opts)` — starts and registers the process.
  Supported options:
  - `:name` — name to register under. Default: `RankPercentile`.
  - `:clock` — a zero-arity function returning the current time in milliseconds.
    Default: `fn -> System.monotonic_time(:millisecond) end`.
  - `:window_ms` — positive integer enabling a **time-based** window. A sample
    recorded at time `t` is live while `now - t < window_ms`. Optional.
  - `:max_samples` — positive integer enabling a **count-based** window (most
    recent N samples retained per series, oldest dropped first). Optional.

  Both windows may be combined; both then apply.

- `RankPercentile.record(name, value)` — records a numeric `value`, timestamped
  with the current clock time. Returns `:ok`.

- `RankPercentile.query(name, percentile)` — the **forward** query. Computes the
  requested percentile over live samples using the **nearest-rank** method
  (`rank = max(1, ceil(p * n))`, return the value at that 1-indexed rank in
  ascending order). `percentile` is a float in `0.0..1.0`. Returns `{:ok, value}`
  (one of the recorded samples) or `{:error, :empty}`.

- `RankPercentile.rank(name, value)` — the **inverse** query. Returns
  `{:ok, q}` where `q` is the fraction of live samples less than or equal to
  `value` (the empirical CDF at `value`), a float in `0.0..1.0`, or
  `{:error, :empty}` when the series has no live samples. A `value` below the
  minimum yields `0.0`; a `value` at or above the maximum yields `1.0`.

- `RankPercentile.count_above(name, threshold)` — returns `{:ok, count}` where
  `count` is the number of live samples strictly greater than `threshold`.
  Returns `{:ok, 0}` for an empty or unknown series (never `:empty`).

- `RankPercentile.reset(name)` — discards all samples for series `name`.
  Returns `:ok`.

## Semantics

- Series are fully independent.
- Time-based expiration is applied at query time; expired samples contribute to
  none of `query/2`, `rank/2`, or `count_above/2`, nor to the count `n`.
- A fully expired or never-recorded series reports `{:error, :empty}` from
  `query/2` and `rank/2`, and `{:ok, 0}` from `count_above/2`.

## Constraints

Give me the complete module in a single file. Use only the OTP standard library —
no external dependencies (a sorted list or similar is fine).