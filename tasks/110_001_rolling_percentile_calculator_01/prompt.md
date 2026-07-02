# Rolling Percentile Calculator

Write me an Elixir GenServer module called `Percentile` that maintains rolling
windows of numeric samples and computes percentiles on demand. A single running
process manages many independent **series**, each identified by an arbitrary
`name` term.

## Public API

- `Percentile.start_link(opts)` — starts and registers the process.
  Supported options:
  - `:name` — the name to register the process under. Default: `Percentile`.
  - `:clock` — a zero-arity function returning the current time in
    milliseconds. Default: `fn -> System.monotonic_time(:millisecond) end`.
    Every timestamp used for window expiration must come from this function so
    that time can be controlled deterministically in tests.
  - `:window_ms` — a positive integer enabling a **time-based** window. A sample
    recorded at time `t` is included in queries as long as `now - t < window_ms`;
    it expires (is excluded) once `now - t >= window_ms`. If omitted, no
    time-based expiration occurs.
  - `:max_samples` — a positive integer enabling a **count-based** window. Only
    the most recently recorded `max_samples` samples per series are retained; when
    a new sample pushes a series over the limit, the oldest sample in that series
    is dropped. If omitted, the sample count is unbounded.

  Both `:window_ms` and `:max_samples` may be supplied together, in which case
  both constraints apply.

- `Percentile.record(name, value)` — records a numeric `value` (integer or float)
  into the series `name`, timestamped with the current clock time. Returns `:ok`.

- `Percentile.query(name, percentile)` — computes the requested percentile over
  the currently-live samples of series `name`. `percentile` is a float in the
  inclusive range `0.0..1.0` (e.g. `0.95` for p95). Returns `{:ok, value}` where
  `value` is one of the recorded samples, or `{:error, :empty}` when the series
  has no live samples (never recorded, fully expired, or reset).

- `Percentile.reset(name)` — discards all samples for series `name`. Returns `:ok`.

The default-registered process name (`Percentile`) is used by `record/2`,
`query/2`, and `reset/1`, so those three functions take only the series `name`,
not a server reference.

## Percentile definition (nearest-rank)

Use the **nearest-rank** method so results are exactly reproducible. Given the
`n` live samples of a series sorted in ascending order as `s_1, s_2, …, s_n`
(1-indexed), for a percentile `p`:

```
rank  = max(1, ceil(p * n))
value = s_rank
```

Consequences you must satisfy:
- `p = 0.0` returns the minimum live sample.
- `p = 1.0` returns the maximum live sample.
- For samples `1..100`, `query(name, 0.50)` returns `50`, `0.95` returns `95`,
  and `0.99` returns `99`.

## Window semantics

- Series are fully independent: recording, querying, or resetting one series must
  never affect another.
- Time-based expiration must be applied at query time (so advancing the clock and
  then querying reflects the newly-expired samples), and expired samples must not
  contribute to the count `n` used in the nearest-rank computation.
- A series whose samples have all expired must report `{:error, :empty}`.

## Constraints

Give me the complete module in a single file. Use only the OTP standard library —
no external dependencies (no t-digest libraries; a sorted list or similar is fine).