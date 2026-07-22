Write me an Elixir GenServer module called `StreamingPercentile` that maintains multiple named numeric streams and computes **percentile queries** (p50, p95, p99, or any arbitrary quantile) over a sliding count-based window.

Instead of computing a single mean, this module answers quantile queries. The window is count-based — "the last N pushed values per stream" — and the quantile is computed via linear interpolation between the two nearest ranks (the same method used by most statistics libraries and databases).

I need these functions in the public API:

- `StreamingPercentile.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `StreamingPercentile.push(server, name, value, window_size)` which appends a numeric value to the named stream's sliding window. `window_size` is the maximum number of values retained for that stream (positive integer). If `window_size` changes on subsequent pushes for the same stream, use the **largest window_size ever seen** for that stream as the effective retention bound — matching the pattern from MovingAverage where `max_period` grows over time and never shrinks. Returns `:ok`.

- `StreamingPercentile.percentile(server, name, q)` where `q` is a float in `[0.0, 1.0]` (e.g. `0.5` for the median, `0.95` for p95). Returns `{:ok, float}` or `{:error, :no_data}` if no values have been pushed yet.

- `StreamingPercentile.percentiles(server, name, q_list)` — batch form, computes multiple percentiles in a single call. `q_list` is a non-empty list of floats in `[0.0, 1.0]`. Returns `{:ok, %{q => float}}` mapping each input `q` to its result, or `{:error, :no_data}`. This matters for performance: sorting is done once and all quantiles are computed against the same sorted snapshot.

- `StreamingPercentile.window(server, name)` — inspection helper returning `{:ok, [float]}` with the current window contents in insertion order (oldest → newest), or `{:error, :no_data}`. Useful for debugging and tests.

**Quantile algorithm.** For a sorted window of N values (smallest first) and a quantile `q`:

1. If N == 1, return the single value.
2. Compute `rank = q * (N - 1)` (floating point, in `[0, N-1]`).
3. Let `lo = floor(rank)` and `hi = ceil(rank)`.
4. If `lo == hi`, return `sorted[lo]` exactly.
5. Otherwise, interpolate: `sorted[lo] + (rank - lo) * (sorted[hi] - sorted[lo])`.

This is the linear-interpolation method (NumPy's default `method="linear"`, Excel's PERCENTILE.INC). Edge cases: `q = 0.0` returns the minimum; `q = 1.0` returns the maximum.

**Internal representation.** The window is maintained as a plain list of values in **insertion order**, newest-first, bounded by the current `max_window_size`. On each `push/4`:

1. Prepend the new value.
2. Trim to at most `max_window_size` entries.

At query time (`percentile/3` or `percentiles/3`):

1. Snapshot-sort the current window into ascending order.
2. Evaluate the quantile formula above (once per `q` in the batch form, but only one sort total).

Sorting on every query is O(N log N). This is the intended implementation — a more sophisticated skip-list or order-statistics tree would be out of scope. What matters is that the quantile semantics are correct, especially around interpolation and edge cases.

**Validation.**

- `push/4` with non-numeric `value` or non-positive `window_size` raises `FunctionClauseError`.
- `percentile/3` with `q` outside `[0.0, 1.0]` returns `{:error, :invalid_quantile}`.
- `percentiles/3` with any `q` outside `[0.0, 1.0]` returns `{:error, :invalid_quantile}` — no partial results.

Different stream names are completely independent.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.