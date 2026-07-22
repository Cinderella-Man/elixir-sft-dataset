  @doc """
  Handles store, fetch and list calls against the in-memory event map.
  """
  @spec handle_call(term(), GenServer.from(), %{events: map()}) ::
          {:reply, term(), %{events: map()}}
  @impl GenServer
  def handle_call({:store_event, event_id, payload}, _from, %{events: events} = state) do
    if Map.has_key?(events, event_id) do
      {:reply, {:ok, :duplicate}, state}
    else
      event = %{event_id: event_id, payload: payload, status: :pending}
      {:reply, {:ok, :created}, %{state | events: Map.put(events, event_id, event)}}
    end
  end

  @impl GenServer
  def handle_call({:get_event, event_id}, _from, %{events: events} = state) do
    case Map.fetch(events, event_id) do
      {:ok, event} -> {:reply, {:ok, event}, state}
      :error -> {:reply, :error, state}
    end
  end

  @impl GenServer
  def handle_call(:all_events, _from, %{events: events} = state) do
    {:reply, Map.values(events), state}
  end