  # Index items into a map of id → node and a list of ids in original order.
  @spec index_items([node_map()]) :: {%{id() => node_map()}, [id()]}
  defp index_items(items) do
    Enum.reduce(items, {%{}, []}, fn item, {map, ids} ->
      id = Map.fetch!(item, :id)
      {Map.put(map, id, item), [id | ids]}
    end)
    |> then(fn {map, ids} -> {map, Enum.reverse(ids)} end)
  end