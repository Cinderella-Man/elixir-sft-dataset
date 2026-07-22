  defp build_closure(_inherits, [], acc), do: acc

  defp build_closure(inherits, [node | rest], acc) do
    if MapSet.member?(acc, node) do
      build_closure(inherits, rest, acc)
    else
      parents = inherits |> Map.get(node, MapSet.new()) |> MapSet.to_list()
      build_closure(inherits, parents ++ rest, MapSet.put(acc, node))
    end
  end