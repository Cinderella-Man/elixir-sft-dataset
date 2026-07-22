  defp flatten(id, id_to_node, children_map, depth, ancestor_path) do
    node = Map.fetch!(id_to_node, id)
    path = ancestor_path ++ [id]

    annotated =
      node
      |> Map.put(:depth, depth)
      |> Map.put(:path, path)

    child_ids = Map.get(children_map, id, [])

    descendants =
      Enum.flat_map(child_ids, fn child_id ->
        flatten(child_id, id_to_node, children_map, depth + 1, path)
      end)

    [annotated | descendants]
  end