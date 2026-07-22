  @spec do_remove(map(), String.t()) :: map()
  defp do_remove(state, id) do
    case Map.get(state.docs, id) do
      nil ->
        state

      doc ->
        postings = remove_postings(state.postings, id, doc.terms)
        %{state | docs: Map.delete(state.docs, id), postings: postings}
    end
  end