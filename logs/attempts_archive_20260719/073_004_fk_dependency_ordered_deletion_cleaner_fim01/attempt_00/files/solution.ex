  defp kahn(spec, node_set, indeg, acc) do
    ready =
      indeg
      |> Enum.filter(fn {_n, d} -> d == 0 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    case ready do
      [] ->
        if map_size(indeg) == 0 do
          {:ok, Enum.reverse(acc)}
        else
          {:error, {:cycle, indeg |> Map.keys() |> Enum.sort()}}
        end

      [n | _] ->
        indeg2 = Map.delete(indeg, n)

        indeg3 =
          Enum.reduce(deps(spec, n, node_set), indeg2, fn b, acc2 ->
            Map.update!(acc2, b, &(&1 - 1))
          end)

        kahn(spec, node_set, indeg3, [n | acc])
    end
  end