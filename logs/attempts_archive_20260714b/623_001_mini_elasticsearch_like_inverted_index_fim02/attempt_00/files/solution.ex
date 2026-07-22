  defp do_remove(state, id) do
    case Map.pop(state.docs, id) do
      {nil, _docs} ->
        state

      {tokenized_fields, docs} ->
        # Collect every unique term that appeared in this document.
        terms_in_doc =
          tokenized_fields
          |> Enum.flat_map(fn {_field, tokens} -> tokens end)
          |> Enum.uniq()

        {postings, doc_freq} =
          Enum.reduce(terms_in_doc, {state.postings, state.doc_freq}, fn term, {p, df} ->
            case Map.get(p, term) do
              nil ->
                {p, df}

              doc_map ->
                doc_map = Map.delete(doc_map, id)

                p =
                  if map_size(doc_map) == 0,
                    do: Map.delete(p, term),
                    else: Map.put(p, term, doc_map)

                new_df = Map.get(df, term, 1) - 1

                df =
                  if new_df <= 0,
                    do: Map.delete(df, term),
                    else: Map.put(df, term, new_df)

                {p, df}
            end
          end)

        %{state | docs: docs, postings: postings, doc_freq: doc_freq}
    end
  end