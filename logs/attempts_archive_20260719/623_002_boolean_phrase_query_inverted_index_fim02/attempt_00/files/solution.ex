  defp do_remove(state, id) do
    case Map.pop(state.documents, id) do
      {nil, _documents} ->
        state

      {tokenized, documents} ->
        terms = doc_terms(tokenized)

        postings =
          Enum.reduce(terms, state.postings, fn term, acc ->
            drop_posting(acc, term, id)
          end)

        %{state | documents: documents, postings: postings}
    end
  end