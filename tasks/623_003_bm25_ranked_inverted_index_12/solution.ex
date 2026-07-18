  @impl GenServer
  def handle_call({:index, id, fields}, _from, state) do
    state = do_remove(state, id)
    {terms, lengths} = build_document(fields, state.stop_words)
    doc = %{terms: terms, lengths: lengths}
    postings = add_postings(state.postings, id, terms)
    {:reply, :ok, %{state | docs: Map.put(state.docs, id, doc), postings: postings}}
  end

  def handle_call({:remove, id}, _from, state) do
    {:reply, :ok, do_remove(state, id)}
  end

  def handle_call({:search, query, opts}, _from, state) do
    boosts = Keyword.get(opts, :boosts, %{})
    limit = Keyword.get(opts, :limit)
    query_terms = query |> tokenize(state.stop_words) |> Enum.uniq()
    results = do_search(state, query_terms, boosts)
    results = if limit, do: Enum.take(results, limit), else: results
    {:reply, results, state}
  end

  def handle_call({:suggest, prefix, limit}, _from, state) do
    prefix = String.downcase(prefix)

    terms =
      state.postings
      |> Enum.filter(fn {term, _ids} -> String.starts_with?(term, prefix) end)
      |> Enum.sort_by(fn {_term, ids} -> MapSet.size(ids) end, :desc)
      |> Enum.take(limit)
      |> Enum.map(fn {term, _ids} -> term end)

    {:reply, terms, state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      document_count: map_size(state.docs),
      term_count: map_size(state.postings)
    }

    {:reply, stats, state}
  end