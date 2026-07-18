  @impl true
  def handle_call({:store, content}, _from, state) do
    hash = sha1_hex(content)
    objects = Map.put_new(state.objects, hash, content)
    {:reply, {:ok, hash}, %{state | objects: objects}}
  end

  def handle_call({:retrieve, hash}, _from, state) do
    case Map.fetch(state.objects, hash) do
      {:ok, content} -> {:reply, {:ok, content}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:commit, tree, parents, message, author}, _from, state) do
    object = build_commit_object(tree, parents, message, author)
    hash = sha1_hex(object)
    objects = Map.put_new(state.objects, hash, object)
    {:reply, {:ok, hash}, %{state | objects: objects}}
  end

  def handle_call({:log, hash}, _from, state) do
    {:reply, do_log(state.objects, hash), state}
  end

  def handle_call({:merge_base, a, b}, _from, state) do
    {:reply, do_merge_base(state.objects, a, b), state}
  end