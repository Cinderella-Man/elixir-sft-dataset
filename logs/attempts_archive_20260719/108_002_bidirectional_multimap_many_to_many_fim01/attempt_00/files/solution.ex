  # Drops `member` from the set stored at `k`, pruning the key when it empties.
  defp remove_assoc(map, k, member) do
    case Map.fetch(map, k) do
      {:ok, set} ->
        set = MapSet.delete(set, member)
        if MapSet.size(set) == 0, do: Map.delete(map, k), else: Map.put(map, k, set)

      :error ->
        map
    end
  end