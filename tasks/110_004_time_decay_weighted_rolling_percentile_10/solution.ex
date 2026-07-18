  @impl true
  def handle_call({:record, name, value}, _from, state) do
    now = state.clock.()
    existing = Map.get(state.series, name, [])
    updated = enforce_max([{now, value} | existing], state.max_samples)
    {:reply, :ok, %{state | series: Map.put(state.series, name, updated)}}
  end

  def handle_call({:query, name, percentile}, _from, state) do
    weighted = weighted_samples(state, name)
    {:reply, weighted_rank(weighted, percentile), state}
  end

  def handle_call({:total_weight, name}, _from, state) do
    weighted = weighted_samples(state, name)
    w = Enum.reduce(weighted, 0.0, fn {_v, w}, acc -> acc + w end)
    result = if weighted == [] or w == 0.0, do: {:error, :empty}, else: {:ok, w}
    {:reply, result, state}
  end

  def handle_call({:reset, name}, _from, state) do
    {:reply, :ok, %{state | series: Map.delete(state.series, name)}}
  end