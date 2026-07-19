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

Write me an Elixir GenServer module called `WeightedMovingAverage` that maintains multiple named streams of numeric values and computes **Weighted Moving Average (WMA)** and **Hull Moving Average (HMA)** on demand.

Unlike SMA (which treats every value in the window equally) or EMA (which geometrically decays older values), WMA assigns **linear weights**: the newest value gets weight `N`, the second newest gets weight `N-1`, down to the oldest in-window value with weight `1`. HMA is a composite — it's the WMA of `2*WMA(period/2) - WMA(period)` with a final WMA of `sqrt(period)`. HMA is used in technical analysis for its reduced lag relative to WMA while preserving smoothness.

I need these functions in the public API:

- `WeightedMovingAverage.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `WeightedMovingAverage.push(server, name, value)` which appends a numeric value to the named stream. Returns `:ok`. The `value` must be a number — guard the function with `is_number/1` so that a non-numeric `value` (e.g. an atom) raises `FunctionClauseError`.

- `WeightedMovingAverage.get(server, name, type, period)` which computes an average over the named stream. `type` is either `:wma` or `:hma`, and `period` is a positive integer. Guard the function so that any `type` other than `:wma` or `:hma` raises `FunctionClauseError`. Returns `{:ok, float}` or `{:error, :no_data}` if no values have been pushed, or `{:error, :insufficient_data}` if the stream has fewer values than needed to produce a meaningful HMA (specifically, when `:hma` is requested and the stream has fewer than `period` values; `:wma` with fewer values falls back to cold-start over whatever is available).

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
