Write me an Elixir GenServer module called `MovingAverage` that maintains multiple named streams of numeric values and computes Simple Moving Averages (SMA) and Exponential Moving Averages (EMA) on demand.

I need these functions in the public API:

- `MovingAverage.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `MovingAverage.push(server, name, value)` which appends a numeric value to the named stream. Returns `:ok`.

- `MovingAverage.get(server, name, type, period)` which computes an average over the named stream. `type` is either `:sma` or `:ema`, and `period` is a positive integer for the window size. Returns `{:ok, result}` where result is a float, or `{:error, :no_data}` if no values have been pushed to that name yet.

SMA is the arithmetic mean of the last `period` values. If fewer than `period` values have been pushed, compute the mean of all available values (cold-start behavior).

EMA uses the standard multiplier `k = 2 / (period + 1)`. Compute it iteratively over the full history of pushed values: seed the EMA with the first value, then for each subsequent value apply `ema = value * k + prev_ema * (1 - k)`. If fewer than `period` values exist, still compute the EMA over whatever is available using the same formula. The EMA calculation must always use the full history from the first value pushed, not just the last `period` values — but you should not need to store all history to do this. Store only the running EMA value per (name, period) pair.

Memory constraints are important:

- For SMA, do not store unbounded history: keep only the last `max_period` values per stream, where `max_period` is the largest period that has ever been requested via `get` for that stream name. Enforce this bound when handling `get`, not on every `push` — so that after requesting a small period you can push more values and then request a larger period and still get the correct mean of those newly pushed values. Once an earlier `get` has trimmed the buffer, those discarded values are gone for good: a later `get` with a much larger period can only average the values still retained (roughly the last `max_period`), not the full stream.

- For EMA, do not rely on the retained SMA values to compute it — because that buffer is bounded, it cannot reproduce the full-history EMA. Instead keep a running accumulator per (name, period) pair. Each time `push` is called, update all existing EMA accumulators for that stream so they keep reflecting the full history from the first value pushed. When `get` is called for an EMA period that hasn't been seen before, compute its EMA from the values currently available and then register the accumulator for future incremental updates.

Different stream names must be completely independent — pushing to "sensor:1" must not affect "sensor:2".

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.
