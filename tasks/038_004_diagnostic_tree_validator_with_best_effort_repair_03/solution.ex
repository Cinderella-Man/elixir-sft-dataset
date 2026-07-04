  defp build_forest(items, known) do
    id_to_node = Map.new(items, fn item -> {item.id, item} end)
    ordered_ids = Enum.map(items, & &1.id)
    children_map = build_children_map(items)

    root_ids =
      Enum.filter(ordered_ids, fn id ->
        pid = Map.fetch!(id_to_node, id).parent_id
        is_nil(pid) or not MapSet.member?(known, pid)
      end)

    Enum.map(root_ids, &build_subtree(&1, id_to_node, children_map))
  end