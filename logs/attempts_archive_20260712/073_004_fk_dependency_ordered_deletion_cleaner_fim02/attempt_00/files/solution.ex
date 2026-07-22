  def deletion_order(spec) when is_map(spec) do
    nodes = Map.keys(spec)
    node_set = MapSet.new(nodes)

    indeg =
      Enum.reduce(nodes, Map.new(nodes, &{&1, 0}), fn a, acc ->
        Enum.reduce(deps(spec, a, node_set), acc, fn b, acc2 ->
          Map.update!(acc2, b, &(&1 + 1))
        end)
      end)

    kahn(spec, node_set, indeg, [])
  end