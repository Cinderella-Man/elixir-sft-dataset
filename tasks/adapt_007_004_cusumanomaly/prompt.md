# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule MovingAverage do
  @moduledoc """
  A GenServer that maintains multiple named numeric streams and computes
  Simple Moving Averages (SMA) and Exponential Moving Averages (EMA) on demand.

  ## State layout

      %{
        streams: %{
          stream_name => %{
            values:      [float]  # newest-first list; trimmed at get/4 time, never at push/3 time
            max_period:  integer  # largest period ever seen via get/4
            total_count: integer  # total number of values pushed (monotonically increasing)
            ema:         %{period => float}  # running EMA accumulator per period
          }
        }
      }

  ## Memory contract

    * **SMA** — `values` is a plain list trimmed to `max_period` entries **at get time**,
      but only when the requested period does not cause `max_period` to grow.  When a
      larger period is first seen, the buffer is left untouched so that the wider
      window has access to all values accumulated since the last trim.  After any
      same-or-smaller-period `get/4` call the buffer length is ≤ `max_period`.
    * **EMA** — one `float` accumulator per `(name, period)` pair.  `push/3` updates
      every registered accumulator in O(distinct EMA periods).  A new EMA period
      bootstraps from the full current `values` buffer *before* any trimming occurs,
      then is maintained incrementally on future pushes.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the `MovingAverage` server.

  ## Options

    * `:name` – optional registration name passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  Appends `value` to the named stream.  Creates the stream on first use.
  Always returns `:ok`.
  """
  @spec push(GenServer.server(), term(), number()) :: :ok
  def push(server, name, value) do
    GenServer.call(server, {:push, name, value})
  end

  @doc """
  Computes an average over the named stream.

    * `type`   – `:sma` or `:ema`
    * `period` – positive integer window size

  Returns `{:ok, float}` or `{:error, :no_data}` if nothing has been pushed yet.
  """
  @spec get(GenServer.server(), term(), :sma | :ema, pos_integer()) ::
          {:ok, float()} | {:error, :no_data}
  def get(server, name, type, period)
      when type in [:sma, :ema] and is_integer(period) and period > 0 do
    GenServer.call(server, {:get, name, type, period})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(:ok) do
    {:ok, %{streams: %{}}}
  end

  @impl GenServer
  def handle_call({:push, name, value}, _from, state) do
    stream =
      state
      |> stream_for(name)
      |> push_value(value)

    {:reply, :ok, put_stream(state, name, stream)}
  end

  def handle_call({:get, name, type, period}, _from, state) do
    stream = stream_for(state, name)

    if stream.total_count == 0 do
      {:reply, {:error, :no_data}, state}
    else
      {result, stream} = compute(stream, type, period)
      {:reply, {:ok, result}, put_stream(state, name, stream)}
    end
  end

  # ---------------------------------------------------------------------------
  # Stream helpers
  # ---------------------------------------------------------------------------

  defp stream_for(state, name) do
    Map.get(state.streams, name, new_stream())
  end

  defp put_stream(state, name, stream) do
    %{state | streams: Map.put(state.streams, name, stream)}
  end

  defp new_stream do
    %{
      # newest-first plain list; never trimmed during push
      values: [],
      max_period: 0,
      total_count: 0,
      ema: %{}
    }
  end

  # ---------------------------------------------------------------------------
  # push_value/2
  #
  # Prepends the value and updates every registered EMA accumulator.
  # Deliberately does NOT trim `values` — trimming is deferred to compute/3
  # so that a later get/4 with a larger period can still see all recent values.
  # ---------------------------------------------------------------------------

  defp push_value(stream, value) when is_number(value) do
    value = value * 1.0

    updated_emas =
      Map.new(stream.ema, fn {period, prev_ema} ->
        {period, ema_step(prev_ema, value, period)}
      end)

    %{
      stream
      | values: [value | stream.values],
        total_count: stream.total_count + 1,
        ema: updated_emas
    }
  end

  # ---------------------------------------------------------------------------
  # compute/3
  #
  # Trimming policy (applied after the result is computed):
  #   • If `period` > current `max_period`  →  max_period GROWS; do NOT trim.
  #     The buffer keeps all values so a subsequent get with this larger period
  #     can still see them on future calls.
  #   • If `period` ≤ current `max_period`  →  max_period stays; TRIM to max_period.
  #     This is the steady-state path that enforces the memory bound.
  #
  # For EMA the bootstrap always reads the pre-trim buffer so it uses the
  # maximum available history.
  # ---------------------------------------------------------------------------

  defp compute(stream, :sma, period) do
    {grew, stream} = maybe_grow_max_period(stream, period)
    stream = if grew, do: stream, else: trim_values(stream)

    window = Enum.take(stream.values, period)
    sma = Enum.sum(window) / length(window)
    {sma, stream}
  end

  defp compute(stream, :ema, period) do
    case Map.get(stream.ema, period) do
      nil ->
        # Bootstrap from the full buffer BEFORE any trim (oldest-first).
        ema_val =
          stream.values
          |> Enum.reverse()
          |> bootstrap_ema(period)

        {grew, stream} = maybe_grow_max_period(stream, period)
        stream = if grew, do: stream, else: trim_values(stream)
        stream = %{stream | ema: Map.put(stream.ema, period, ema_val)}
        {ema_val, stream}

      ema_val ->
        # Accumulator already current from incremental push_value updates.
        {grew, stream} = maybe_grow_max_period(stream, period)
        stream = if grew, do: stream, else: trim_values(stream)
        {ema_val, stream}
    end
  end

  # ---------------------------------------------------------------------------
  # EMA arithmetic
  # ---------------------------------------------------------------------------

  # Expects values in oldest-first order.
  defp bootstrap_ema([], _period), do: 0.0

  defp bootstrap_ema([seed | rest], period) do
    Enum.reduce(rest, seed * 1.0, fn value, prev ->
      ema_step(prev, value, period)
    end)
  end

  @compile {:inline, [ema_step: 3]}
  defp ema_step(prev_ema, value, period) do
    k = 2.0 / (period + 1)
    value * k + prev_ema * (1.0 - k)
  end

  # ---------------------------------------------------------------------------
  # Buffer management — called only from compute/3, never from push_value/2
  # ---------------------------------------------------------------------------

  # Returns `{grew?, updated_stream}`.
  defp maybe_grow_max_period(%{max_period: mp} = stream, period) when period > mp,
    do: {true, %{stream | max_period: period}}

  defp maybe_grow_max_period(stream, _period),
    do: {false, stream}

  defp trim_values(%{max_period: 0} = stream), do: stream

  defp trim_values(stream) do
    %{stream | values: Enum.take(stream.values, stream.max_period)}
  end
end
```

## New specification

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

## Additional interface contract

- `start_link/1` validates its options eagerly in the calling process, before any process is started: out-of-range values raise `ArgumentError` directly from the `start_link/1` call (not an `{:error, _}` return). Specifically, `threshold: 0`, `threshold: -1`, `slack: -0.1`, `warmup_samples: 0`, and `epsilon: 0` must each raise `ArgumentError`.
- `start_link` must also be callable with no arguments — declare it as `start_link(opts \\ [])` — in which case every option takes its default.
- The warmup comparison uses the stream's sample count *before* the current push: with `warmup_samples: n`, pushes 1 through n all return `:warming_up` (the n-th push included), and push n+1 is the first CUSUM-active push that can return `:ok` or an alert.
- Warmup pushes still update the Welford accumulators — only the CUSUM step is skipped during warmup. `check/2` on a stream that has received pushes but is still warming up returns `{:ok, info}` (not an error), where `info.samples` counts every push so far and `info.mean`/`info.stddev` reflect all pushed values (population stddev, i.e. `sqrt(M2 / n)`).
- `push/3` must reject a non-numeric `value` by raising `FunctionClauseError` in the caller — put a `when is_number(value)` guard on the public `push/3` function itself; do not return an error tuple and do not let the server crash.
- `reset/2` on an existing stream zeroes its state but keeps the stream known: a subsequent `check/2` returns `{:ok, %{samples: 0, mean: 0.0, ...}}` — reset must not delete the stream entry. Conversely, after `reset/2` on a never-seen stream, `check/2` must still return `{:error, :no_data}`.
- After an alert the stream likewise stays known but frozen: `check/2` then returns `{:ok, %{samples: 0, mean: 0.0, stddev: 0.0, s_high: 0.0, s_low: 0.0, status: :warming_up}}`, and further pushes while frozen leave that state completely untouched (`samples` stays `0` no matter how many frozen pushes arrive before `reset/2`).
