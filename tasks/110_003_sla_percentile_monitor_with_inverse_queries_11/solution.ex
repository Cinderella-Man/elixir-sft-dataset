  @impl true
  def handle_call({:record, name, value}, _from, state) do
    now = state.clock.()
    existing = Map.get(state.series, name, [])
    updated = enforce_max([{now, value} | existing], state.max_samples)
    {:reply, :ok, %{state | series: Map.put(state.series, name, updated)}}
  end

  def handle_call({:query, name, percentile}, _from, state) do
    sorted = live_values(state, name)
    {:reply, percentile_of(sorted, percentile), state}
  end

  def handle_call({:rank, name, value}, _from, state) do
    sorted = live_values(state, name)

    result =
      case sorted do
        [] -> {:error, :empty}
        _ -> {:ok, Enum.count(sorted, &(&1 <= value)) / length(sorted)}
      end

    {:reply, result, state}
  end

  def handle_call({:count_above, name, threshold}, _from, state) do
    count = state |> live_values(name) |> Enum.count(&(&1 > threshold))
    {:reply, {:ok, count}, state}
  end

  def handle_call({:reset, name}, _from, state) do
    {:reply, :ok, %{state | series: Map.delete(state.series, name)}}
  end