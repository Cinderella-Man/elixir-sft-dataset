  defp remove_doc(state, id) do
    case Map.fetch(state.docs, id) do
      :error ->
        state

      {:ok, counts} ->
        index =
          Enum.reduce(counts, state.index, fn {term, _count}, idx ->
            case Map.fetch(idx, term) do
              :error ->
                idx

              {:ok, postings} ->
                pruned = Map.delete(postings, id)

                if map_size(pruned) == 0 do
                  Map.delete(idx, term)
                else
                  Map.put(idx, term, pruned)
                end
            end
          end)

        %{state | docs: Map.delete(state.docs, id), index: index}
    end
  end