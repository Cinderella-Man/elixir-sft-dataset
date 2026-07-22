Write me an Elixir GenServer module called `WeightedMovingAverage` that maintains multiple named streams of numeric values and computes **Weighted Moving Average (WMA)** and **Hull Moving Average (HMA)** on demand.

Unlike SMA (which treats every value in the window equally) or EMA (which geometrically decays older values), WMA assigns **linear weights**: the newest value gets weight `N`, the second newest gets weight `N-1`, down to the oldest in-window value with weight `1`. HMA is a composite — it's the WMA of `2*WMA(period/2) - WMA(period)` with a final WMA of `sqrt(period)`. HMA is used in technical analysis for its reduced lag relative to WMA while preserving smoothness.

I need these functions in the public API:

- `WeightedMovingAverage.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `WeightedMovingAverage.push(server, name, value)` which appends a numeric value to the named stream. Returns `:ok`.

- `WeightedMovingAverage.get(server, name, type, period)` which computes an average over the named stream. `type` is either `:wma` or `:hma`, and `period` is a positive integer. Returns `{:ok, float}` or `{:error, :no_data}` if no values have been pushed, or `{:error, :insufficient_data}` if the stream has fewer values than needed to produce a meaningful HMA (specifically, when `:hma` is requested and the stream has fewer than `period` values; `:wma` with fewer values falls back to cold-start over whatever is available).

**WMA math.** For a window of N values `[v_newest, v2, ..., v_oldest]`, WMA = `(N*v_newest + (N-1)*v2 + ... + 1*v_oldest) / (N + (N-1) + ... + 1)`. The denominator is `N*(N+1)/2`. Cold-start (fewer than `period` values available): compute the WMA over all available values, with weights adjusted — e.g. with 3 of 5 values available, weights are `[3, 2, 1]` and denominator is `6`.

**HMA math.** For `period = P`:
1. Compute `wma1 = WMA(period = P/2)` using integer division.
2. Compute `wma2 = WMA(period = P)`.
3. Compute `raw = 2 * wma1 - wma2`.
4. Maintain a rolling buffer of `raw` values (one per push that happens after the HMA accumulator has been established for this stream/period). The HMA is then `WMA(raw_buffer, period = round(sqrt(P)))`.

HMA must be computed **incrementally** — every push must produce a new `raw` value and append it to the HMA's rolling buffer. When `:hma` is requested with a new `period` for the first time, the buffer must be bootstrapped from the full available history: replay every stored value to build up the `raw` series retroactively, and store the bootstrapped state for future incremental updates.

**Memory constraints.**

- For WMA, keep the last `max_period` values per stream, where `max_period` is the largest period ever requested for that stream (via `:wma` directly OR indirectly via an `:hma` query). Store values newest-first as a plain list.

- For HMA, store per `(name, period)` pair:
  - `raw_buffer` — a list of derived `raw` values, newest-first, bounded by `round(sqrt(period))` entries
  - `wma1_period = div(period, 2)` and `wma2_period = period` are recomputable from `period`, so don't store them

When a push happens and a stream has one or more registered HMA periods, each push must recompute `wma1`, `wma2`, `raw`, and append `raw` to each HMA's `raw_buffer`. This means push is O(distinct HMA periods × max_wma_period) in the worst case — acceptable for finite registered periods.

Different stream names must be completely independent.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.