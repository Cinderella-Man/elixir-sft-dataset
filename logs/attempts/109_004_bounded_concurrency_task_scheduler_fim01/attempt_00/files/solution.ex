defp strip(in_degree, _dependents) when map_size(in_degree) == 0, do: :ok

defp strip(in_degree, dependents) do
  ready = for {id, 0} <- in_degree, do: id

  case ready do
    [] ->
      {:error, {:cycle, Map.keys(in_degree)}}

    _ ->
      remaining = Map.drop(in_degree, ready)
      remaining = decrement_dependents(ready, remaining, dependents)
      strip(remaining, dependents)
  end
end