  @impl true
  def handle_call({:save, metadata}, _from, state) do
    id = uuid_v4()
    uploaded_at = DateTime.utc_now() |> DateTime.to_iso8601()

    record =
      metadata
      |> Map.put(:id, id)
      |> Map.put(:uploaded_at, uploaded_at)

    {:reply, {:ok, record}, put_in(state.files[id], record)}
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