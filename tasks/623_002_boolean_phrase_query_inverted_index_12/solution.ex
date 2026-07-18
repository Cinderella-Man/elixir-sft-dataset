  @impl true
  def handle_call({:index, id, fields}, _from, state) do
    state = do_remove(state, id)

    tokenized =
      fields
      |> Enum.map(fn {field, text} -> {field, tokenize(text, state.stop_words)} end)
      |> Map.new()

    terms = doc_terms(tokenized)

    postings =
      Enum.reduce(terms, state.postings, fn term, acc ->
        Map.update(acc, term, MapSet.new([id]), &MapSet.put(&1, id))
      end)

    documents = Map.put(state.documents, id, tokenized)
    {:reply, :ok, %{state | documents: documents, postings: postings}}
  end

  def handle_call({:remove, id}, _from, state) do
    {:reply, :ok, do_remove(state, id)}
  end

  def handle_call({:search, query}, _from, state) do
    ids = query |> eval(state) |> MapSet.to_list() |> Enum.sort()
    {:reply, ids, state}
  end

  def handle_call({:suggest, prefix, limit}, _from, state) do
    prefix = String.downcase(prefix)

    terms =
      state.postings
      |> Enum.filter(fn {term, _ids} -> String.starts_with?(term, prefix) end)
      |> Enum.sort_by(fn {term, ids} -> {-MapSet.size(ids), term} end)
      |> Enum.take(limit)
      |> Enum.map(fn {term, _ids} -> term end)

    {:reply, terms, state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      document_count: map_size(state.documents),
      term_count: map_size(state.postings)
    }

    {:reply, stats, state}
  end