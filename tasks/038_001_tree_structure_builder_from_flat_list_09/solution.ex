  # Given the back-edge target `cycle_root` and the current DFS path (newest
  # first), return the ids that form the cycle in top-down order.
  @spec extract_cycle(id(), [id()]) :: [id()]
  defp extract_cycle(cycle_root, path) do
    # `path` is [cycle_root, current_node, ..., cycle_root_ancestor, ...]
    # Reverse so it reads oldest-first, drop nodes before the cycle entry
    # point, then deduplicate so cycle_root doesn't appear at both ends.
    path
    |> Enum.reverse()
    |> Enum.drop_while(fn id -> id != cycle_root end)
    |> Enum.uniq()
    |> then(fn
      [] -> [cycle_root]
      slice -> slice
    end)
  end