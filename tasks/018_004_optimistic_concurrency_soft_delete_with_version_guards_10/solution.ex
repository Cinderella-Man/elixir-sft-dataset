  @doc false
  @impl true
  @spec handle_call(term(), GenServer.from(), map()) :: {:reply, term(), map()}
  def handle_call({:create, attrs}, _from, state) do
    case validate_fields(attrs, [:title, :content]) do
      {:ok, f} ->
        id = state.next_id
        t = state.tick

        doc = %{
          id: id,
          title: f.title,
          content: f.content,
          deleted_at: nil,
          lock_version: 0,
          inserted_at: t,
          updated_at: t
        }

        {:reply, {:ok, doc},
         %{state | docs: Map.put(state.docs, id, doc), next_id: id + 1, tick: t + 1}}

      {:error, errors} ->
        {:reply, {:error, errors}, state}
    end
  end

  def handle_call({:list, opts}, _from, state) do
    include_deleted = Keyword.get(opts, :include_deleted, false)

    res =
      state.docs
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.filter(fn d -> include_deleted or d.deleted_at == nil end)

    {:reply, res, state}
  end

  def handle_call({:get, id, opts}, _from, state) do
    include_deleted = Keyword.get(opts, :include_deleted, false)

    reply =
      case Map.get(state.docs, id) do
        nil -> {:error, :not_found}
        d -> if d.deleted_at == nil or include_deleted, do: {:ok, d}, else: {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call({:update, id, attrs, expected}, _from, state) do
    case Map.get(state.docs, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{deleted_at: da} when da != nil ->
        {:reply, {:error, :not_found}, state}

      %{lock_version: v} when v != expected ->
        {:reply, {:error, :stale_version, v}, state}

      doc ->
        case validate_update(attrs, doc) do
          {:ok, ch} ->
            t = state.tick

            updated = %{
              doc
              | title: ch.title,
                content: ch.content,
                lock_version: doc.lock_version + 1,
                updated_at: t
            }

            docs = Map.put(state.docs, id, updated)
            {:reply, {:ok, updated}, %{state | docs: docs, tick: t + 1}}

          {:error, errors} ->
            {:reply, {:error, errors}, state}
        end
    end
  end

  def handle_call({:soft_delete, id, expected}, _from, state) do
    case Map.get(state.docs, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{lock_version: v} when v != expected ->
        {:reply, {:error, :stale_version, v}, state}

      %{deleted_at: da} when da != nil ->
        {:reply, {:error, :already_deleted}, state}

      doc ->
        t = state.tick
        updated = %{doc | deleted_at: t, lock_version: doc.lock_version + 1, updated_at: t}
        {:reply, {:ok, updated}, %{state | docs: Map.put(state.docs, id, updated), tick: t + 1}}
    end
  end

  def handle_call({:restore, id, expected}, _from, state) do
    case Map.get(state.docs, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{lock_version: v} when v != expected ->
        {:reply, {:error, :stale_version, v}, state}

      %{deleted_at: nil} ->
        {:reply, {:error, :not_deleted}, state}

      doc ->
        t = state.tick
        updated = %{doc | deleted_at: nil, lock_version: doc.lock_version + 1, updated_at: t}
        {:reply, {:ok, updated}, %{state | docs: Map.put(state.docs, id, updated), tick: t + 1}}
    end
  end