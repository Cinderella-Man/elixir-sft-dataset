Write me an Elixir GenServer module called `CusumAnomaly` that maintains multiple named numeric streams and detects **change points** using a CUSUM (cumulative sum) algorithm combined with online mean/variance via Welford's algorithm.

The motivation: moving averages smooth a signal but don't tell you when its statistical character has **shifted** — a new equilibrium has been reached that's different from the previous one. CUSUM is a classic sequential change-detection algorithm designed for exactly that. This module is the inverse of a moving average: instead of returning the current average, it returns whether the stream is currently exhibiting an anomalous shift.

**Welford's online algorithm** for mean and variance avoids needing to store history:

    n = 0, mean = 0.0, M2 = 0.0
    for each new value x:
      n += 1
      delta = x - mean
      mean += delta / n
      delta2 = x - mean
      M2 += delta * delta2
    variance = M2 / n             # population variance
    stddev = sqrt(variance)

**Two-sided CUSUM.** Maintain two cumulative sums `s_high` and `s_low` per stream, both starting at 0. On each push with value `x`:

1. Compute a **normalized deviation** `z = (x - mean_before_update) / max(stddev_before_update, epsilon)`. If fewer than `warmup_samples` values have been pushed, skip CUSUM entirely (return `:warming_up` on a check); there's not enough data for z-scoring to be meaningful.
2. If the stream's stddev *before* this update is below `slack`, skip the CUSUM update for this push — just update Welford's accumulators with `x` and return `:ok` (z-scoring against a near-zero stddev is meaningless and would cause false alerts on a flat signal). Otherwise update `s_high = max(0.0, s_high + z - slack)` and `s_low = max(0.0, s_low - z - slack)`. The `slack` (default `0.5`) is a small positive constant that makes CUSUM ignore small deviations around the mean.
3. Finally, update Welford's running mean and variance with `x` (so z-scoring always uses the mean *before* this value).
4. If `s_high >= threshold`, emit an "upward shift" alert: the stream has moved into a higher regime. Reset both CUSUMs and Welford's accumulators entirely to zero and mark the stream as alerted: it is frozen (subsequent pushes are ignored and return `:warming_up`) until the operator calls `reset/2`, after which it re-learns the new regime from scratch.
5. Mirror for `s_low >= threshold`: emit a "downward shift" alert with the same full reset-and-freeze.

Each push records whether an alert fired; subsequent `check/2` queries can return the latest status.

I need these functions in the public API:

- `CusumAnomaly.start_link(opts)` — options:
  - `:name` — optional process registration
  - `:threshold` — alert trigger (positive float, default `5.0`)
  - `:slack` — CUSUM slack constant (non-negative float, default `0.5`)
  - `:warmup_samples` — minimum samples before detection is active (positive integer, default `10`)
  - `:epsilon` — minimum stddev floor to avoid division-by-zero (positive float, default `1.0e-6`)

- `CusumAnomaly.push(server, name, value)` — appends `value` to the stream and performs the CUSUM/Welford update. Returns one of:
  - `:ok` — value processed, no alert fired
  - `{:alert, :upward_shift}` — upper CUSUM breached threshold; both CUSUMs and Welford state are reset
  - `{:alert, :downward_shift}` — lower CUSUM breached threshold; both CUSUMs and Welford state are reset
  - `:warming_up` — stream still has fewer than `warmup_samples` values (CUSUM not yet active), or the stream is frozen after a previous alert and is awaiting an explicit `reset/2`

  Only one direction can alert per push (if both simultaneously exceed threshold, `:upward_shift` wins and the stream is reset-and-frozen as above — this is vanishingly rare and not worth special handling).

- `CusumAnomaly.check(server, name)` — reports the stream's current status without pushing a value. Returns `{:ok, %{mean: float, stddev: float, s_high: float, s_low: float, samples: non_neg_integer, status: :normal | :warming_up}}` where `status` is `:warming_up` if `samples < warmup_samples`, else `:normal`. Returns `{:error, :no_data}` if the stream is completely unknown.

- `CusumAnomaly.reset(server, name)` — explicitly resets the stream's Welford and CUSUM state to zero and clears any post-alert freeze. Useful when the operator knows a regime change has occurred. Returns `:ok` (does not create a stream if one doesn't exist).

Different stream names are independent.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.