  defp dedup(items) do
    {kept, _seen, dups} =
      Enum.reduce(items, {[], MapSet.new(), []}, fn item, {kept, seen, dups} ->
        if MapSet.member?(seen, item.id) do
          {kept, seen, [item.id | dups]}
        else
          {[item | kept], MapSet.put(seen, item.id), dups}
        end
      end)

    {Enum.reverse(kept), dups |> Enum.reverse() |> Enum.uniq()}
  end