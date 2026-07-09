Implement the private `bootstrap_raw_buffer/3` function. It is called the first time
`:hma` is requested for a given `(stream, period)` pair, and its job is to reconstruct
the HMA's rolling `raw` buffer from the stream's full available history so that future
pushes can update it incrementally.

It receives three arguments: `values_newest_first` (the stream's stored values, a
newest-first list of floats), `period` (the requested HMA period `P`), and `buffer_size`
(the buffer bound, already computed by the caller as `round(sqrt(period))`).

Derive the two WMA periods from `period`: `wma1_period = div(period, 2)` and
`wma2_period = period`. Then replay the history in chronological (oldest→newest) order.
For each successive point in time, take the slice of history available *up to and
including that point* — in a newest-first list, the history up to the value at index `i`
(where index `0` is the newest) is that list with its first `i` elements dropped — and
compute `raw = 2 * WMA(window, wma1_period) - WMA(window, wma2_period)` over that slice
using `compute_wma/2`. Walk `i` from `length(values) - 1` down to `0` so the resulting
`raw` values come out oldest-first.

Finally, return the buffer the way it is stored elsewhere: newest-first and bounded to at
most `buffer_size` entries. Since the replay produced the raws oldest-first, reverse them
to newest-first and keep only the most recent `buffer_size` values.

```elixir
defmodule WeightedMovingAverage do
  @moduledoc """
  A GenServer that maintains multiple named numeric streams and computes
  Weighted Moving Average (WMA) and Hull Moving Average (HMA) on demand.

  ## WMA

  Linear weights over the last `period` values, newest weighted `N`:

      WMA = sum(weight_i * v_i) / sum(weight_i)

  where `weight_i = period - i` for `i` in `0..period-1` with `v_0` the
  newest value.  Cold-start (fewer values than `period`): compute WMA over
  all available values using adjusted weights.

  ## HMA

  For period P:

      wma1 = WMA(P / 2)
      wma2 = WMA(P)
      raw  = 2 * wma1 - wma2
      hma  = WMA(raw_series, round(sqrt(P)))

  HMA is maintained incrementally: every push recomputes `raw` and appends
  it to a per-(stream, period) rolling buffer bounded at `round(sqrt(P))`.

  ## State layout

      %{
        streams: %{
          stream_name => %{
            values:     [float],         # newest-first, bounded by max_period
            max_period: non_neg_integer,
            hma:        %{period => %{raw_buffer :: [float]}}
          }
        }
      }

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @spec push(GenServer.server(), term(), number()) :: :ok
  def push(server, name, value) when is_number(value) do
    GenServer.call(server, {:push, name, value})
  end

  @spec get(GenServer.server(), term(), :wma | :hma, pos_integer()) ::
          {:ok, float()} | {:error, :no_data | :insufficient_data}
  def get(server, name, type, period)
      when type in [:wma, :hma] and is_integer(period) and period > 0 do
    GenServer.call(server, {:get, name, type, period})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(:ok), do: {:ok, %{streams: %{}}}

  @impl GenServer
  def handle_call({:push, name, value}, _from, state) do
    stream =
      state
      |> stream_for(name)
      |> push_value(value)

    {:reply, :ok, put_stream(state, name, stream)}
  end

  def handle_call({:get, name, :wma, period}, _from, state) do
    stream = stream_for(state, name)

    if stream.values == [] do
      {:reply, {:error, :no_data}, state}
    else
      stream = maybe_grow_max_period(stream, period)
      stream = trim_values(stream)
      {:reply, {:ok, compute_wma(stream.values, period)}, put_stream(state, name, stream)}
    end
  end

  def handle_call({:get, name, :hma, period}, _from, state) do
    stream = stream_for(state, name)

    cond do
      stream.values == [] ->
        {:reply, {:error, :no_data}, state}

      length(stream.values) < period ->
        {:reply, {:error, :insufficient_data}, state}

      true ->
        {result, stream} = compute_hma(stream, period)
        {:reply, {:ok, result}, put_stream(state, name, stream)}
    end
  end

  # ---------------------------------------------------------------------------
  # Stream bookkeeping
  # ---------------------------------------------------------------------------

  defp stream_for(state, name), do: Map.get(state.streams, name, new_stream())

  defp put_stream(state, name, stream),
    do: %{state | streams: Map.put(state.streams, name, stream)}

  defp new_stream do
    %{
      # newest-first
      values: [],
      max_period: 0,
      # %{period => %{raw_buffer: [float]}}
      hma: %{}
    }
  end

  # ---------------------------------------------------------------------------
  # push_value/2
  #
  # Appends the value to `values`, then for every registered HMA period
  # recomputes `raw` and appends it to that period's raw_buffer.
  #
  # We deliberately do NOT trim `values` here — trimming is deferred until a
  # `:wma` or `:hma` get observes the current max_period.
  # ---------------------------------------------------------------------------

  defp push_value(stream, value) do
    value = value * 1.0
    new_values = [value | stream.values]

    new_hma =
      Map.new(stream.hma, fn {period, hma_state} ->
        wma1_period = div(period, 2)
        wma2_period = period

        # Use the NEW values list (includes this push).
        wma1 = compute_wma(new_values, wma1_period)
        wma2 = compute_wma(new_values, wma2_period)
        raw = 2 * wma1 - wma2

        buffer_size = round(:math.sqrt(period))
        new_buffer = [raw | hma_state.raw_buffer] |> Enum.take(buffer_size)

        {period, %{hma_state | raw_buffer: new_buffer}}
      end)

    %{stream | values: new_values, hma: new_hma}
  end

  # ---------------------------------------------------------------------------
  # WMA computation
  # ---------------------------------------------------------------------------

  # values: newest-first list; period: how many values the WMA wants.
  # Cold-start when fewer values are available: uses whatever's there with
  # adjusted weights.  Weights: newest = N, next = N-1, ..., oldest = 1.
  defp compute_wma([], _period), do: 0.0

  defp compute_wma(values, period) do
    window = Enum.take(values, period)
    n = length(window)

    # window is newest-first, so weight decreases as we move toward the tail
    {weighted_sum, weight_sum} =
      window
      |> Enum.with_index()
      |> Enum.reduce({0.0, 0}, fn {v, i}, {ws, wt} ->
        weight = n - i
        {ws + v * weight, wt + weight}
      end)

    weighted_sum / weight_sum
  end

  # ---------------------------------------------------------------------------
  # HMA computation
  # ---------------------------------------------------------------------------

  # Called only when length(stream.values) >= period.
  defp compute_hma(stream, period) do
    buffer_size = round(:math.sqrt(period))

    {hma_state, stream} =
      case Map.get(stream.hma, period) do
        nil ->
          # Bootstrap from full available history.
          buffer = bootstrap_raw_buffer(stream.values, period, buffer_size)
          hma_state = %{raw_buffer: buffer}

          # Grow max_period to cover period (and period/2).
          stream =
            stream
            |> maybe_grow_max_period(period)
            |> put_hma(period, hma_state)

          {hma_state, stream}

        existing ->
          stream = maybe_grow_max_period(stream, period)
          {existing, stream}
      end

    # Final WMA of the raw_buffer with window = round(sqrt(period))
    hma_value = compute_wma(hma_state.raw_buffer, buffer_size)

    # Only trim after HMA accumulator is set up — trimming before bootstrap
    # would lose history the bootstrap needed.
    stream = trim_values(stream)

    {hma_value, stream}
  end

  # Replays historical values oldest-first to build up the raw_buffer
  # incrementally, keeping the last buffer_size derived values.
  defp bootstrap_raw_buffer(values_newest_first, period, buffer_size) do
    # TODO
  end

  defp put_hma(stream, period, hma_state) do
    %{stream | hma: Map.put(stream.hma, period, hma_state)}
  end

  # ---------------------------------------------------------------------------
  # Buffer management
  # ---------------------------------------------------------------------------

  defp maybe_grow_max_period(%{max_period: mp} = stream, period) when period > mp,
    do: %{stream | max_period: period}

  defp maybe_grow_max_period(stream, _period), do: stream

  defp trim_values(%{max_period: 0} = stream), do: stream

  defp trim_values(stream) do
    %{stream | values: Enum.take(stream.values, stream.max_period)}
  end
end
```