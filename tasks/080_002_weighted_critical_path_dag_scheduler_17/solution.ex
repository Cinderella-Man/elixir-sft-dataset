  defp dfs_reaches?(out_edges, start, target) do
    do_dfs([start], MapSet.new(), out_edges, target)
  end