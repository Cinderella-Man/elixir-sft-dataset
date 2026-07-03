  @impl true
  def handle_call({:save, hash, metadata}, _from, state) do
    case Map.fetch(state.files, hash) do
      {:ok, record} ->
        updated = %{record | upload_count: record.upload_count + 1}
        {:reply, {:ok, :exists, updated}, put_in(state.files[hash], updated)}

      :error ->
        record =
          metadata
          |> Map.put(:id, hash)
          |> Map.put(:uploaded_at, DateTime.utc_now() |> DateTime.to_iso8601())
          |> Map.put(:upload_count, 1)

        {:reply, {:ok, :created, record}, put_in(state.files[hash], record)}
    end
  end

  def handle_call({:get, id}, _from, state) do
    case Map.fetch(state.files, id) do
      {:ok, record} -> {:reply, {:ok, record}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.files), state}
  end