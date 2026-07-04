  # Recursively build a tree node, attaching children.
  @spec build_subtree(id(), %{id() => node_map()}, %{id() => [id()]}) :: tree_node()
  defp build_subtree(id, id_to_node, children_map) do
    node = Map.fetch!(id_to_node, id)
    child_ids = Map.get(children_map, id, [])

    children =
      Enum.map(child_ids, fn child_id ->
        build_subtree(child_id, id_to_node, children_map)
      end)

    Map.put(node, :children, children)
  end