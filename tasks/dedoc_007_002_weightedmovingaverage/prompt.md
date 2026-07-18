# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule WeightedMovingAverage do
  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def push(server, name, value) when is_number(value) do
    GenServer.call(server, {:push, name, value})
  end

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
    wma1_period = div(period, 2)
    wma2_period = period

    # Rebuild prefixes: for each suffix (oldest→newest), compute raw over the
    # values available *up to that point*.  values[k..end] in newest-first is
    # the "history up to value at index k" where index 0 is the newest.
    total = length(values_newest_first)

    # For each position i (0 = newest), the "history-so-far" is values[i..]
    # (newest-first), which corresponds to all values up to and including the
    # i-th-from-newest value.  Walk from oldest-position (total-1) down to 0
    # so we emit raw values in chronological order.
    raws_oldest_first =
      for i <- (total - 1)..0//-1 do
        window = Enum.drop(values_newest_first, i)
        wma1 = compute_wma(window, wma1_period)
        wma2 = compute_wma(window, wma2_period)
        2 * wma1 - wma2
      end

    # Convert to newest-first and take the last `buffer_size` raws.
    raws_oldest_first
    |> Enum.reverse()
    |> Enum.take(buffer_size)
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
