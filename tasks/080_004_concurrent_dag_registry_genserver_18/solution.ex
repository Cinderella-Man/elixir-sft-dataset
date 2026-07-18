  # Kahn's algorithm, sorted for determinism.
  defp topo_order(state) do
    in_degree =
      Map.new(state.vertices, fn v -> {v, MapSet.size(Map.fetch!(state.in_edges, v))} end)

    initial =
      in_degree
      |> Enum.filter(fn {_v, d} -> d == 0 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    kahn(initial, in_degree, state.out_edges, [])
  end