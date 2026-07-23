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

# Design Brief: `StreamingPercentile`

## Problem

We need an Elixir GenServer module called `StreamingPercentile` that maintains multiple named numeric streams and computes **percentile queries** (p50, p95, p99, or any arbitrary quantile) over a sliding count-based window.

Instead of computing a single mean, this module answers quantile queries. The window is count-based — "the last N pushed values per stream" — and the quantile is computed via linear interpolation between the two nearest ranks (the same method used by most statistics libraries and databases).

## Constraints

- Deliver the complete module in a single file.
- Use only OTP standard library, no external dependencies.
- Different stream names are completely independent.

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

## Required Interface

These functions must appear in the public API:

1. `StreamingPercentile.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

2. `StreamingPercentile.push(server, name, value, window_size)` which appends a numeric value to the named stream's sliding window. `window_size` is the maximum number of values retained for that stream (positive integer). If `window_size` changes on subsequent pushes for the same stream, use the **largest window_size ever seen** for that stream as the effective retention bound — matching the pattern from MovingAverage where `max_period` grows over time and never shrinks. Returns `:ok`. Pushed values are coerced to floats, so window contents and all percentile results are floats (e.g. pushing integer `42` yields `42.0`).

3. `StreamingPercentile.percentile(server, name, q)` where `q` is a float in `[0.0, 1.0]` (e.g. `0.5` for the median, `0.95` for p95). Returns `{:ok, float}` or `{:error, :no_data}` if no values have been pushed yet.

4. `StreamingPercentile.percentiles(server, name, q_list)` — batch form, computes multiple percentiles in a single call. `q_list` is a non-empty list of floats in `[0.0, 1.0]`. Returns `{:ok, %{q => float}}` mapping each input `q` to its result, or `{:error, :no_data}`. This matters for performance: sorting is done once and all quantiles are computed against the same sorted snapshot.

5. `StreamingPercentile.window(server, name)` — inspection helper returning `{:ok, [float]}` with the current window contents in insertion order (oldest → newest), or `{:error, :no_data}`. Useful for debugging and tests.

## Acceptance Criteria

**Validation.**

- `push/4` with non-numeric `value` or non-positive `window_size` raises `FunctionClauseError`.
- `percentile/3` with `q` outside `[0.0, 1.0]` returns `{:error, :invalid_quantile}`.
- `percentiles/3` with any `q` outside `[0.0, 1.0]` returns `{:error, :invalid_quantile}` — no partial results.
