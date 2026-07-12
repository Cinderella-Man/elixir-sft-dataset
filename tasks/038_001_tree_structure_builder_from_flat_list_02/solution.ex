  def build([], _opts), do: {:ok, []}

  def build(items, opts) when is_list(items) do
    orphan_strategy = Keyword.get(opts, :orphan_strategy, :discard)

    # Index nodes by id, preserving insertion order via a list of ids.
    {id_to_node, ordered_ids} = index_items(items)

    # Validate: duplicate ids are detected early.
    case detect_duplicate_ids(items) do
      {:error, _} = err ->
        err

      :ok ->
        # Build a parent_id → [child_id] map (children in original order).
        children_map = build_children_map(items)

        # Determine which nodes are "known" ids.
        known_ids = MapSet.new(ordered_ids)

        # Detect cycles using DFS on the children graph before we build anything.
        case detect_cycle(ordered_ids, children_map) do
          {:error, _} = err ->
            err

          :ok ->
            # Identify root nodes: parent_id is nil, OR parent_id is unknown
            # (orphan handling) — depending on strategy.
            root_ids =
              ordered_ids
              |> Enum.filter(fn id ->
                node = Map.fetch!(id_to_node, id)
                pid = node.parent_id

                cond do
                  is_nil(pid) ->
                    true

                  not MapSet.member?(known_ids, pid) ->
                    orphan_strategy == :raise_to_root

                  true ->
                    false
                end
              end)

            forest =
              Enum.map(root_ids, fn id ->
                build_subtree(id, id_to_node, children_map)
              end)

            {:ok, forest}
        end
    end
  end
