  @impl GenServer
  def handle_call({:create_folder, attrs}, _from, state) do
    with {:ok, name} <- validate_name(Map.get(attrs, :name)),
         parent_id = Map.get(attrs, :parent_id),
         :ok <- validate_parent(state, parent_id, :optional) do
      do_create(state, %{type: :folder, name: name, parent_id: parent_id, content: nil})
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:create_file, attrs}, _from, state) do
    with {:ok, name} <- validate_name(Map.get(attrs, :name)),
         parent_id = Map.get(attrs, :parent_id),
         :ok <- validate_parent(state, parent_id, :required),
         {:ok, content} <- validate_content(Map.get(attrs, :content, "")) do
      do_create(state, %{type: :file, name: name, parent_id: parent_id, content: content})
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:fetch_node, id, include_archived}, _from, state) do
    case Map.fetch(state.nodes, id) do
      {:ok, node} ->
        if include_archived or live?(node) do
          {:reply, {:ok, node}, state}
        else
          {:reply, {:error, :not_found}, state}
        end

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:list_children, folder_id, include_archived}, _from, state) do
    with {:ok, folder} <- Map.fetch(state.nodes, folder_id),
         true <- folder.type == :folder,
         true <- include_archived or live?(folder) do
      children =
        state.nodes
        |> Map.values()
        |> Enum.filter(fn child ->
          child.parent_id == folder_id and (include_archived or live?(child))
        end)
        |> Enum.sort_by(& &1.id)

      {:reply, {:ok, children}, state}
    else
      _other -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:rename_node, id, new_name}, _from, state) do
    with {:ok, name} <- validate_name(new_name),
         {:ok, node} <- fetch_live(state, id) do
      updated = %{node | name: name}
      {:reply, {:ok, updated}, put_node(state, updated)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:archive_node, id}, _from, state) do
    case Map.fetch(state.nodes, id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, node} ->
        if live?(node) do
          do_archive(state, node)
        else
          {:reply, {:error, :already_archived}, state}
        end
    end
  end

  def handle_call({:unarchive_node, id}, _from, state) do
    with {:ok, node} <- Map.fetch(state.nodes, id),
         :ok <- check_archived(node),
         :ok <- check_direct(node),
         :ok <- check_parent_live(state, node) do
      do_unarchive(state, node)
    else
      :error -> {:reply, {:error, :not_found}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:list_archived, _from, state) do
    archived =
      state.nodes
      |> Map.values()
      |> Enum.reject(&live?/1)
      |> Enum.sort_by(& &1.id)

    {:reply, {:ok, archived}, state}
  end