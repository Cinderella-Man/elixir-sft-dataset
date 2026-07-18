  @spec matching_series(map(), String.t(), labels()) :: [map()]
  defp matching_series(state, metric, matchers) do
    state.series
    |> Enum.filter(fn {{name, _sorted}, entry} ->
      name == metric and matches?(entry.labels, matchers)
    end)
    |> Enum.map(fn {_key, entry} -> entry end)
  end