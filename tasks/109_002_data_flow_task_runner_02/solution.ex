defp build_layers(in_degree, _dependents, layers) when map_size(in_degree) == 0 do
  {:ok, Enum.reverse(layers)}
end

defp build_layers(in_degree, dependents, layers) do
  ready = for {id, 0} <- in_degree, do: id

  case ready do
    [] ->
      {:error, {:cycle, cycle_nodes(Map.keys(in_degree), dependents)}}

    _ ->
      remaining = Map.drop(in_degree, ready)

      remaining =
        Enum.reduce(ready, remaining, fn id, acc ->
          dependents
          |> Map.get(id, [])
          |> Enum.reduce(acc, fn dependent, acc2 ->
            case Map.fetch(acc2, dependent) do
              {:ok, n} -> Map.put(acc2, dependent, n - 1)
              :error -> acc2
            end
          end)
        end)

      build_layers(remaining, dependents, [ready | layers])
  end
end