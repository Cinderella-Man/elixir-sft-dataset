  @spec walk([hash], %{optional(hash) => binary()}, MapSet.t(hash)) :: MapSet.t(hash)
  defp walk([], _objects, acc), do: acc

  defp walk([hash | rest], objects, acc) do
    cond do
      MapSet.member?(acc, hash) ->
        walk(rest, objects, acc)

      not Map.has_key?(objects, hash) ->
        walk(rest, objects, acc)

      true ->
        acc = MapSet.put(acc, hash)
        extra = commit_refs(Map.fetch!(objects, hash))
        walk(extra ++ rest, objects, acc)
    end
  end