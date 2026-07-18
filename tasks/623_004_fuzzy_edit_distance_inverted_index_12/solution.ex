  @impl GenServer
  def handle_call({:index, id, text}, _from, state) do
    state = remove_doc(state, id)
    counts = text |> tokenize(state.stop_words) |> token_counts()

    index =
      Enum.reduce(counts, state.index, fn {term, count}, idx ->
        Map.update(idx, term, %{id => count}, fn postings ->
          Map.put(postings, id, count)
        end)
      end)

    new_state = %{state | docs: Map.put(state.docs, id, counts), index: index}
    {:reply, :ok, new_state}
  end

  def handle_call({:remove, id}, _from, state) do
    {:reply, :ok, remove_doc(state, id)}
  end

  def handle_call({:search, query, opts}, _from, state) do
    max_distance = Keyword.get(opts, :max_distance, 1)
    limit = Keyword.get(opts, :limit)
    {:reply, do_search(state, query, max_distance, limit), state}
  end

  def handle_call({:terms_like, term, max_distance}, _from, state) do
    lowered = String.downcase(term)

    result =
      state.index
      |> Map.keys()
      |> Enum.map(fn t -> {t, edit_distance(lowered, t)} end)
      |> Enum.filter(fn {_t, d} -> d <= max_distance end)
      |> Enum.sort_by(fn {t, d} -> {d, t} end)
      |> Enum.map(fn {t, _d} -> t end)

    {:reply, result, state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{document_count: map_size(state.docs), term_count: map_size(state.index)}
    {:reply, stats, state}
  end