# Time-Decay Weighted Rolling Percentile

Write me an Elixir GenServer module called `DecayPercentile` that computes
percentiles over samples whose influence **fades continuously with age** rather
than dropping off a hard window edge. A single running process manages many
independent **series**, each identified by an arbitrary `name` term.

Instead of a live/expired boolean, every sample carries an exponentially-decaying
weight based on how long ago it was recorded. Recent samples dominate; old
samples still count, but progressively less. This gives smooth, drift-aware
percentiles with no abrupt jumps when a sample crosses a boundary.

## Public API

- `DecayPercentile.start_link(opts)` — starts and registers the process.
  Supported options:
  - `:name` — name to register under. Default: `DecayPercentile`.
  - `:clock` — a zero-arity function returning the current time in milliseconds.
    Default: `fn -> System.monotonic_time(:millisecond) end`. All ages are
    computed from this clock.
  - `:half_life_ms` — **required** positive integer. A sample of age `a` has
    weight `0.5 ^ (a / half_life_ms)` (weight `1.0` when just recorded, `0.5` at
    one half-life, `0.25` at two, and so on). Anything else raises `ArgumentError`.
  - `:max_samples` — optional positive integer bounding retained samples per
    series (oldest dropped first) so memory stays bounded.

- The `name` argument of `record/2`, `query/2`, `total_weight/1`, and `reset/1` is purely the **series** name — these helpers always call the server registered under the default `DecayPercentile` name (the `:name` start option changes process registration only, not how the helpers address the server).
- `DecayPercentile.record(name, value)` — records a numeric `value`, timestamped
  with the current clock time. Returns `:ok`.

- `DecayPercentile.query(name, percentile)` — computes the **weighted nearest-rank**
  percentile over the current samples of series `name`. `percentile` is a float in
  `0.0..1.0`. Returns `{:ok, value}` where `value` is one of the recorded samples,
  or `{:error, :empty}` when the series has no samples (or all weights have
  underflowed to zero). A sample whose weight has underflowed to zero is
  excluded from selection entirely — it can never be the returned value, at
  any percentile.

- `DecayPercentile.total_weight(name)` — returns `{:ok, w}` where `w` is the sum
  of the current decayed weights (a float), or `{:error, :empty}` under the same
  emptiness rule as `query` (no samples, or every weight underflowed to zero —
  never `{:ok, 0.0}`). Useful as an "effective sample count" for inspection.

- `DecayPercentile.reset(name)` — discards all samples for series `name`.
  Returns `:ok`.

## Weighted nearest-rank definition

At query time compute each sample's weight `w_i = 0.5 ^ ((now - t_i)/half_life_ms)`.
Sort the samples ascending by **value** as `(v_1, w_1), …, (v_n, w_n)` and let
`W = Σ w_i`. For a percentile `p`, walk the sorted list accumulating weight and
return the value `v_j` at the first position where the cumulative weight reaches
`p * W`:

```
target = p * W
return the first v_j where (w_1 + … + w_j) >= target
```

Consequences:
- `p = 0.0` returns the minimum-valued sample; `p = 1.0` returns the maximum.
- Doubling a sample's freshness (halving its age relative to others) can move the
  reported percentile toward that sample's value.
- **Uniform aging is neutral**: if no new samples arrive, advancing the clock
  scales every weight by the same factor, so the reported percentile is unchanged.

## Semantics

- Series are fully independent.

## Constraints

Give me the complete module in a single file. Use only the OTP standard library —
no external dependencies. `:math.pow/2` is fine for the decay factor.