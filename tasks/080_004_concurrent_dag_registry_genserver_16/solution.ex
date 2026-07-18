  defp check_no_cycle(_state, from, from), do: {:error, :cycle}

  defp check_no_cycle(state, from, to) do
    if dfs_reaches?(state.out_edges, to, from), do: {:error, :cycle}, else: :ok
  end