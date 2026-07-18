  defp inc(state, keys) do
    metrics = Enum.reduce(keys, state.metrics, fn k, m -> Map.update!(m, k, &(&1 + 1)) end)
    %{state | metrics: metrics}
  end