  @impl GenServer
  def handle_call(
        {:store_event, provider, event_id, payload},
        _from,
        %{events: events} = state
      ) do
    key = {provider, event_id}

    if Map.has_key?(events, key) do
      {:reply, {:ok, :duplicate}, state}
    else
      event = %{provider: provider, event_id: event_id, payload: payload, status: :pending}
      {:reply, {:ok, :created}, %{state | events: Map.put(events, key, event)}}
    end
  end

  @impl GenServer
  def handle_call({:get_event, provider, event_id}, _from, %{events: events} = state) do
    case Map.fetch(events, {provider, event_id}) do
      {:ok, event} -> {:reply, {:ok, event}, state}
      :error -> {:reply, :error, state}
    end
  end

  @impl GenServer
  def handle_call(:all_events, _from, %{events: events} = state) do
    {:reply, Map.values(events), state}
  end