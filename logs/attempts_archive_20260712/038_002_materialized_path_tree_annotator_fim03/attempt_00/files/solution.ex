  def build(items, opts \\ [])

  def build([], _opts), do: {:ok, []}

  def build(items, opts) when is_list(items) do
    orphan_strategy = Keyword.get(opts, :orphan_strategy, :discard)

    {id_to_node, ordered_ids} = index_items(items)

    case detect_duplicate_ids(items) do
      {:error, _} = err ->
        err

      :ok ->
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
                  not MapSet.member?(known_ids, pid) -> orphan_strategy == :raise_to_root
                  true -> false
                end
              end)

            nodes =
              Enum.flat_map(root_ids, fn id ->
                flatten(id, id_to_node, children_map, 0, [])
              end)

            {:ok, nodes}
        end
    end
  end