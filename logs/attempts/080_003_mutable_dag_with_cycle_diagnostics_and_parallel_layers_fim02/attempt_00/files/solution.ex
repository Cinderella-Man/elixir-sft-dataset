  defp build_layers(in_degree, out_edges, acc) do
    if map_size(in_degree) == 0 do
      Enum.reverse(acc)
    else
      layer =
        in_degree
        |> Enum.filter(fn {_v, d} -> d == 0 end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()

      remaining = Map.drop(in_degree, layer)

      new_in_degree =
        Enum.reduce(layer, remaining, fn v, deg ->
          Enum.reduce(Map.get(out_edges, v, MapSet.new()), deg, fn s, d ->
            Map.update!(d, s, &(&1 - 1))
          end)
        end)

      build_layers(new_in_degree, out_edges, [layer | acc])
    end
  end