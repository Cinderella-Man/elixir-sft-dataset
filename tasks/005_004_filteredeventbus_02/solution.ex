  # Path navigation: maps by key, lists by integer index.  Missing keys → nil.
  defp fetch(value, []), do: value

  defp fetch(map, [key | rest]) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, v} -> fetch(v, rest)
      :error -> nil
    end
  end

  defp fetch(list, [idx | rest]) when is_list(list) and is_integer(idx) do
    case Enum.at(list, idx, :__missing__) do
      :__missing__ -> nil
      v -> fetch(v, rest)
    end
  end

  defp fetch(_, _), do: nil