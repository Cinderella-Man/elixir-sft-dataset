  @doc false
  @impl true
  @spec handle_call(term(), GenServer.from(), map()) :: {:reply, term(), map()}
  def handle_call({:create, metadata}, _from, state) do
    record =
      metadata
      |> Map.put(:id, uuid_v4())
      |> Map.put(:uploaded_at, DateTime.utc_now() |> DateTime.to_iso8601())
      |> Map.put(:status, :pending)

    {:reply, {:ok, record}, put_in(state.files[record.id], record)}
  end

  def handle_call({:update_status, id, status, extra}, _from, state) do
    case Map.fetch(state.files, id) do
      {:ok, record} ->
        updated = record |> Map.merge(extra) |> Map.put(:status, status)
        {:reply, :ok, put_in(state.files[id], updated)}

      :error ->
        {:reply, {:error, :not_found}, state}
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