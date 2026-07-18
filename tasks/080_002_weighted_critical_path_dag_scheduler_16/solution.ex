  defp check_no_cycle(_dag, from, from), do: {:error, :cycle}

  defp check_no_cycle(dag, from, to) do
    if dfs_reaches?(dag.out_edges, to, from), do: {:error, :cycle}, else: :ok
  end