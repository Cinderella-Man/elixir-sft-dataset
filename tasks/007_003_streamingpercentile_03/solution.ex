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