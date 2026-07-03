  defp follow(nil, _po, _target, _seen), do: false

  defp follow(node, po, target, seen) do
    cond do
      node == target -> true
      MapSet.member?(seen, node) -> false
      true -> follow(po[node], po, target, MapSet.put(seen, node))
    end
  end