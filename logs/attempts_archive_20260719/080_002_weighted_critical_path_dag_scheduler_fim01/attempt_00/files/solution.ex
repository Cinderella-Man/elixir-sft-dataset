  defp compute_est(dag) do
    Enum.reduce(topo_order(dag), %{}, fn v, est ->
      preds = Map.fetch!(dag.in_edges, v)

      start =
        if MapSet.size(preds) == 0 do
          0
        else
          preds
          |> Enum.map(fn p -> Map.fetch!(est, p) + Map.fetch!(dag.durations, p) end)
          |> Enum.max()
        end

      Map.put(est, v, start)
    end)
  end