  defp do_build([], _strategy), do: {:ok, []}

  defp do_build(items, strategy) do
    {id_to_node, ordered_ids} = index_items(items)
    children_map = build_children_map(items)
    known_ids = MapSet.new(ordered_ids)

    case detect_cycle(ordered_ids, children_map) do
      {:error, _} = err ->
        err

      :ok ->
        root_ids =
          Enum.filter(ordered_ids, fn id ->
            pid = Map.fetch!(id_to_node, id).parent_id

            cond do
              is_nil(pid) -> true
              not MapSet.member?(known_ids, pid) -> strategy == :raise_to_root
              true -> false
            end
          end)

        forest = Enum.map(root_ids, &build_subtree(&1, id_to_node, children_map))
        {:ok, forest}
    end
  end