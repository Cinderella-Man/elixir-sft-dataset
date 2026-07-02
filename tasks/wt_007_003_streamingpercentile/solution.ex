defmodule StreamingPercentile do
  @moduledoc """
  A GenServer that maintains multiple named numeric streams as sliding
  count-based windows and answers arbitrary-quantile queries via linear
  interpolation between the two nearest ranks.

  ## Quantile definition

  For a sorted window `s` of `N` values (ascending) and a quantile `q` in
  `[0.0, 1.0]`:

      rank = q * (N - 1)
      lo   = floor(rank);  hi = ceil(rank)
      lo == hi -> sorted[lo]
      else     -> sorted[lo] + (rank - lo) * (sorted[hi] - sorted[lo])

  This is the linear-interpolation method — NumPy's default `"linear"`,
  Excel's `PERCENTILE.INC`, the method described by Hyndman & Fan (1996)
  as type 7.

  ## State layout

      %{
        streams: %{
          stream_name => %{
            values:           [float],  # newest-first, bounded by max_window_size
            max_window_size:  pos_integer
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

  @spec push(GenServer.server(), term(), number(), pos_integer()) :: :ok
  def push(server, name, value, window_size)
      when is_number(value) and is_integer(window_size) and window_size > 0 do
    GenServer.call(server, {:push, name, value, window_size})
  end

  @spec percentile(GenServer.server(), term(), float()) ::
          {:ok, float()} | {:error, :no_data | :invalid_quantile}
  def percentile(server, name, q) when is_float(q) or is_integer(q) do
    if valid_quantile?(q) do
      GenServer.call(server, {:percentile, name, q * 1.0})
    else
      {:error, :invalid_quantile}
    end
  end

  @spec percentiles(GenServer.server(), term(), [float(), ...]) ::
          {:ok, %{float() => float()}} | {:error, :no_data | :invalid_quantile}
  def percentiles(server, name, [_ | _] = q_list) do
    if Enum.all?(q_list, &valid_quantile?/1) do
      GenServer.call(server, {:percentiles, name, Enum.map(q_list, &(&1 * 1.0))})
    else
      {:error, :invalid_quantile}
    end
  end

  @spec window(GenServer.server(), term()) ::
          {:ok, [float()]} | {:error, :no_data}
  def window(server, name), do: GenServer.call(server, {:window, name})

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(:ok), do: {:ok, %{streams: %{}}}

  @impl GenServer
  def handle_call({:push, name, value, window_size}, _from, state) do
    stream = stream_for(state, name)

    new_max = max(stream.max_window_size, window_size)
    new_values = [value * 1.0 | stream.values] |> Enum.take(new_max)

    new_stream = %{stream | values: new_values, max_window_size: new_max}
    {:reply, :ok, put_stream(state, name, new_stream)}
  end

  def handle_call({:percentile, name, q}, _from, state) do
    stream = stream_for(state, name)

    if stream.values == [] do
      {:reply, {:error, :no_data}, state}
    else
      sorted = Enum.sort(stream.values)
      {:reply, {:ok, quantile(sorted, q)}, state}
    end
  end

  def handle_call({:percentiles, name, q_list}, _from, state) do
    stream = stream_for(state, name)

    if stream.values == [] do
      {:reply, {:error, :no_data}, state}
    else
      sorted = Enum.sort(stream.values)
      results = Map.new(q_list, fn q -> {q, quantile(sorted, q)} end)
      {:reply, {:ok, results}, state}
    end
  end

  def handle_call({:window, name}, _from, state) do
    stream = stream_for(state, name)

    if stream.values == [] do
      {:reply, {:error, :no_data}, state}
    else
      # Return in insertion order (oldest → newest).
      {:reply, {:ok, Enum.reverse(stream.values)}, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Quantile math — operates on an already-sorted ascending list
  # ---------------------------------------------------------------------------

  defp quantile([only], _q), do: only

  defp quantile(sorted, q) do
    n = length(sorted)
    rank = q * (n - 1)

    lo_idx = trunc(rank)
    hi_idx = min(lo_idx + 1, n - 1)

    lo_val = Enum.at(sorted, lo_idx)

    if lo_idx == hi_idx do
      lo_val
    else
      hi_val = Enum.at(sorted, hi_idx)
      frac = rank - lo_idx
      lo_val + frac * (hi_val - lo_val)
    end
  end

  # ---------------------------------------------------------------------------
  # Stream helpers
  # ---------------------------------------------------------------------------

  defp stream_for(state, name),
    do: Map.get(state.streams, name, new_stream())

  defp put_stream(state, name, stream),
    do: %{state | streams: Map.put(state.streams, name, stream)}

  defp new_stream, do: %{values: [], max_window_size: 0}

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  defp valid_quantile?(q) when is_number(q), do: q >= 0.0 and q <= 1.0
  defp valid_quantile?(_), do: false
end
