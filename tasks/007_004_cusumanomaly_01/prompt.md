# Design brief: `CusumAnomaly` change-point detector

## Problem

Moving averages smooth a signal but don't tell you when its statistical character has **shifted** — a new equilibrium has been reached that's different from the previous one. CUSUM (cumulative sum) is a classic sequential change-detection algorithm designed for exactly that. We need a module that is the inverse of a moving average: instead of returning the current average, it returns whether a stream is currently exhibiting an anomalous shift.

Build an Elixir GenServer module called `CusumAnomaly` that maintains multiple named numeric streams and detects **change points** using a CUSUM algorithm combined with online mean/variance via Welford's algorithm. Different stream names are independent.

## Constraints

- Deliver the complete module in a single file.
- Use only the OTP standard library — no external dependencies.

### Algorithm 1 — Welford's online mean and variance (avoids storing history)

    n = 0, mean = 0.0, M2 = 0.0
    for each new value x:
      n += 1
      delta = x - mean
      mean += delta / n
      delta2 = x - mean
      M2 += delta * delta2
    variance = M2 / n             # population variance
    stddev = sqrt(variance)

### Algorithm 2 — Two-sided CUSUM

Maintain two cumulative sums `s_high` and `s_low` per stream, both starting at 0. On each push with value `x`:

1. Compute a **normalized deviation** `z = (x - mean_before_update) / max(stddev_before_update, epsilon)`. If fewer than `warmup_samples` values have been pushed, skip CUSUM entirely (return `:warming_up` on a check); there's not enough data for z-scoring to be meaningful.
2. If the stream's stddev *before* this update is below `slack`, skip the CUSUM update for this push — just update Welford's accumulators with `x` and return `:ok` (z-scoring against a near-zero stddev is meaningless and would cause false alerts on a flat signal). Otherwise update `s_high = max(0.0, s_high + z - slack)` and `s_low = max(0.0, s_low - z - slack)`. The `slack` (default `0.5`) is a small positive constant that makes CUSUM ignore small deviations around the mean.
3. Finally, update Welford's running mean and variance with `x` (so z-scoring always uses the mean *before* this value).
4. If `s_high >= threshold`, emit an "upward shift" alert: the stream has moved into a higher regime. Reset both CUSUMs and Welford's accumulators entirely to zero and mark the stream as alerted: it is frozen (subsequent pushes are ignored and return `:warming_up`) until the operator calls `reset/2`, after which it re-learns the new regime from scratch.
5. Mirror for `s_low >= threshold`: emit a "downward shift" alert with the same full reset-and-freeze.

Each push records whether an alert fired; subsequent `check/2` queries can return the latest status.

## Required interface

1. `CusumAnomaly.start_link(opts)` — options:
   - `:name` — optional process registration
   - `:threshold` — alert trigger (positive float, default `5.0`)
   - `:slack` — CUSUM slack constant (non-negative float, default `0.5`)
   - `:warmup_samples` — minimum samples before detection is active (positive integer, default `10`)
   - `:epsilon` — minimum stddev floor to avoid division-by-zero (positive float, default `1.0e-6`)

2. `CusumAnomaly.push(server, name, value)` — appends `value` to the stream and performs the CUSUM/Welford update. Returns one of:
   - `:ok` — value processed, no alert fired
   - `{:alert, :upward_shift}` — upper CUSUM breached threshold; both CUSUMs and Welford state are reset
   - `{:alert, :downward_shift}` — lower CUSUM breached threshold; both CUSUMs and Welford state are reset
   - `:warming_up` — stream still has fewer than `warmup_samples` values (CUSUM not yet active), or the stream is frozen after a previous alert and is awaiting an explicit `reset/2`

   Only one direction can alert per push (if both simultaneously exceed threshold, `:upward_shift` wins and the stream is reset-and-frozen as above — this is vanishingly rare and not worth special handling).

3. `CusumAnomaly.check(server, name)` — reports the stream's current status without pushing a value. Returns `{:ok, %{mean: float, stddev: float, s_high: float, s_low: float, samples: non_neg_integer, status: :normal | :warming_up}}` where `status` is `:warming_up` if `samples < warmup_samples`, else `:normal`. Returns `{:error, :no_data}` if the stream is completely unknown.

4. `CusumAnomaly.reset(server, name)` — explicitly resets the stream's Welford and CUSUM state to zero and clears any post-alert freeze. Useful when the operator knows a regime change has occurred. Returns `:ok` (does not create a stream if one doesn't exist).

## Acceptance criteria

- `start_link/1` validates its options eagerly in the calling process, before any process is started: out-of-range values raise `ArgumentError` directly from the `start_link/1` call (not an `{:error, _}` return). Specifically, `threshold: 0`, `threshold: -1`, `slack: -0.1`, `warmup_samples: 0`, and `epsilon: 0` must each raise `ArgumentError`.
- `start_link` must also be callable with no arguments — declare it as `start_link(opts \\ [])` — in which case every option takes its default.
- The warmup comparison uses the stream's sample count *before* the current push: with `warmup_samples: n`, pushes 1 through n all return `:warming_up` (the n-th push included), and push n+1 is the first CUSUM-active push that can return `:ok` or an alert.
- Warmup pushes still update the Welford accumulators — only the CUSUM step is skipped during warmup. `check/2` on a stream that has received pushes but is still warming up returns `{:ok, info}` (not an error), where `info.samples` counts every push so far and `info.mean`/`info.stddev` reflect all pushed values (population stddev, i.e. `sqrt(M2 / n)`).
- `push/3` must reject a non-numeric `value` by raising `FunctionClauseError` in the caller — put a `when is_number(value)` guard on the public `push/3` function itself; do not return an error tuple and do not let the server crash.
- `reset/2` on an existing stream zeroes its state but keeps the stream known: a subsequent `check/2` returns `{:ok, %{samples: 0, mean: 0.0, ...}}` — reset must not delete the stream entry. Conversely, after `reset/2` on a never-seen stream, `check/2` must still return `{:error, :no_data}`.
- After an alert the stream likewise stays known but frozen: `check/2` then returns `{:ok, %{samples: 0, mean: 0.0, stddev: 0.0, s_high: 0.0, s_low: 0.0, status: :warming_up}}`, and further pushes while frozen leave that state completely untouched (`samples` stays `0` no matter how many frozen pushes arrive before `reset/2`).
