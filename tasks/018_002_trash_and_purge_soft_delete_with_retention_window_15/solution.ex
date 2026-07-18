  @impl true
  def handle_call({:create, attrs}, _from, state) do
    case validate_fields(attrs, [:title, :content]) do
      {:ok, f} ->
        now = state.clock.()
        id = state.next_id

        doc = %{
          id: id,
          title: f.title,
          content: f.content,
          deleted_at: nil,
          inserted_at: now,
          updated_at: now
        }

        {:reply, {:ok, doc}, %{state | docs: Map.put(state.docs, id, doc), next_id: id + 1}}

      {:error, errors} ->
        {:reply, {:error, errors}, state}
    end
  end

  def handle_call({:list, opts}, _from, state) do
    now = state.clock.()
    include_deleted = Keyword.get(opts, :include_deleted, false)

    docs =
      state.docs
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.filter(fn doc ->
        include_deleted or status(doc, now, state.retention) == :active
      end)

    {:reply, docs, state}
  end

  def handle_call({:get, id, opts}, _from, state) do
    now = state.clock.()
    include_deleted = Keyword.get(opts, :include_deleted, false)

    reply =
      case Map.get(state.docs, id) do
        nil ->
          {:error, :not_found}

        doc ->
          if status(doc, now, state.retention) == :active or include_deleted do
            {:ok, doc}
          else
            {:error, :not_found}
          end
      end

    {:reply, reply, state}
  end

  def handle_call({:update, id, attrs}, _from, state) do
    now = state.clock.()

    case active_doc(state, id, now) do
      nil ->
        {:reply, {:error, :not_found}, state}

      doc ->
        case validate_update(attrs, doc) do
          {:ok, ch} ->
            updated = %{doc | title: ch.title, content: ch.content, updated_at: now}
            {:reply, {:ok, updated}, %{state | docs: Map.put(state.docs, id, updated)}}

          {:error, errors} ->
            {:reply, {:error, errors}, state}
        end
    end
  end

  def handle_call({:soft_delete, id}, _from, state) do
    now = state.clock.()

    case Map.get(state.docs, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      doc ->
        case status(doc, now, state.retention) do
          :active ->
            updated = %{doc | deleted_at: now, updated_at: now}
            {:reply, {:ok, updated}, %{state | docs: Map.put(state.docs, id, updated)}}

          _ ->
            {:reply, {:ok, doc}, state}
        end
    end
  end

  def handle_call({:restore, id}, _from, state) do
    now = state.clock.()

    case Map.get(state.docs, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      doc ->
        case status(doc, now, state.retention) do
          :active ->
            {:reply, {:ok, doc}, state}

          :trashed ->
            updated = %{doc | deleted_at: nil, updated_at: now}
            {:reply, {:ok, updated}, %{state | docs: Map.put(state.docs, id, updated)}}

          :expired ->
            {:reply, {:error, :expired}, state}
        end
    end
  end

  def handle_call({:purge, id}, _from, state) do
    now = state.clock.()

    case Map.get(state.docs, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      doc ->
        case status(doc, now, state.retention) do
          :active -> {:reply, {:error, :not_deleted}, state}
          _ -> {:reply, {:ok, doc}, %{state | docs: Map.delete(state.docs, id)}}
        end
    end
  end

  def handle_call(:purge_expired, _from, state) do
    now = state.clock.()

    {expired, kept} =
      Enum.split_with(state.docs, fn {_id, doc} ->
        status(doc, now, state.retention) == :expired
      end)

    {:reply, {:ok, length(expired)}, %{state | docs: Map.new(kept)}}
  end