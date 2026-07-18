  defp maybe_add(acc, [], _type), do: acc
  defp maybe_add(acc, ids, type), do: acc ++ [%{type: type, ids: ids}]