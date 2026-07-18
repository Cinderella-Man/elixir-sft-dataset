  @impl true
  def handle_call({:store, content}, _from, state) do
    hash = hash_content(content)
    objects = Map.put_new(state.objects, hash, content)
    {:reply, {:ok, hash}, %{state | objects: objects}}
  end

  def handle_call({:retrieve, hash}, _from, state) do
    case Map.fetch(state.objects, hash) do
      {:ok, content} -> {:reply, {:ok, content}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:commit, tree_hash, parent_hash, message, author}, _from, state) do
    content = serialize_commit(tree_hash, parent_hash, message, author)
    hash = hash_content(content)
    objects = Map.put_new(state.objects, hash, content)
    {:reply, {:ok, hash}, %{state | objects: objects}}
  end

  def handle_call({:create_branch, name, commit_hash}, _from, state) do
    cond do
      Map.has_key?(state.branches, name) ->
        {:reply, {:error, :exists}, state}

      not Map.has_key?(state.objects, commit_hash) ->
        {:reply, {:error, :not_found}, state}

      true ->
        branches = Map.put(state.branches, name, commit_hash)
        {:reply, {:ok, name}, %{state | branches: branches}}
    end
  end

  def handle_call({:branch_head, name}, _from, state) do
    case Map.fetch(state.branches, name) do
      {:ok, commit_hash} -> {:reply, {:ok, commit_hash}, state}
      :error -> {:reply, {:error, :no_branch}, state}
    end
  end

  def handle_call({:update_branch, name, expected_hash, new_hash}, _from, state) do
    cond do
      not Map.has_key?(state.branches, name) ->
        {:reply, {:error, :no_branch}, state}

      not Map.has_key?(state.objects, new_hash) ->
        {:reply, {:error, :not_found}, state}

      Map.fetch!(state.branches, name) != expected_hash ->
        {:reply, {:error, :conflict}, state}

      true ->
        branches = Map.put(state.branches, name, new_hash)
        {:reply, {:ok, new_hash}, %{state | branches: branches}}
    end
  end

  def handle_call({:delete_branch, name}, _from, state) do
    case Map.has_key?(state.branches, name) do
      true -> {:reply, :ok, %{state | branches: Map.delete(state.branches, name)}}
      false -> {:reply, {:error, :no_branch}, state}
    end
  end

  def handle_call(:list_branches, _from, state) do
    {:reply, state.branches, state}
  end

  def handle_call(:gc, _from, state) do
    reachable = reachable_set(state)

    {kept, removed_count} =
      Enum.reduce(state.objects, {%{}, 0}, fn {hash, content}, {acc, count} ->
        case MapSet.member?(reachable, hash) do
          true -> {Map.put(acc, hash, content), count}
          false -> {acc, count + 1}
        end
      end)

    {:reply, {:ok, removed_count}, %{state | objects: kept}}
  end