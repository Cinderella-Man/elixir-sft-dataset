  # Kahn's algorithm (BFS over in-degrees), sorted for determinism.
  defp topo_order(dag) do
    in_degree =
      Map.new(Map.keys(dag.durations), fn v ->
        {v, MapSet.size(Map.fetch!(dag.in_edges, v))}
      end)

    initial =
      in_degree
      |> Enum.filter(fn {_v, d} -> d == 0 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    kahn(initial, in_degree, dag.out_edges, [])
  end