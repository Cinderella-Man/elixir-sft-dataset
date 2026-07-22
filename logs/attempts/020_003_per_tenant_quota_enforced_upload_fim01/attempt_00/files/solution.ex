  @impl true
  def handle_call({:save, account, metadata}, _from, state) do
    used = Map.get(state.usage, account, 0)
    size = metadata.size

    if used + size > state.quota do
      info = %{quota: state.quota, used: used, requested: size}
      {:reply, {:error, :quota_exceeded, info}, state}
    else
      record =
        metadata
        |> Map.put(:id, uuid_v4())
        |> Map.put(:uploaded_at, DateTime.utc_now() |> DateTime.to_iso8601())
        |> Map.put(:account, account)

      new_used = used + size

      state =
        state
        |> put_in([:files, record.id], record)
        |> put_in([:usage, account], new_used)

      {:reply, {:ok, record, %{quota: state.quota, used: new_used}}, state}
    end
  end

  def handle_call({:delete, account, id}, _from, state) do
    case Map.fetch(state.files, id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, %{account: owner}} when owner != account ->
        {:reply, {:error, :forbidden}, state}

      {:ok, record} ->
        used = Map.get(state.usage, account, 0)
        new_used = max(used - record.size, 0)

        state =
          state
          |> update_in([:files], &Map.delete(&1, id))
          |> put_in([:usage, account], new_used)

        {:reply, {:ok, %{record: record, freed: record.size, used: new_used}}, state}
    end
  end

  def handle_call({:get, id}, _from, state) do
    case Map.fetch(state.files, id) do
      {:ok, record} -> {:reply, {:ok, record}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:usage, account}, _from, state) do
    {:reply, Map.get(state.usage, account, 0), state}
  end

  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.files), state}
  end