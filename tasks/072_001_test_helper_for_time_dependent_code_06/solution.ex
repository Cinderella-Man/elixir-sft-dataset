  @impl GenServer
  def handle_call(:now, _from, state), do: {:reply, state, state}

  def handle_call({:freeze, datetime}, _from, _state), do: {:reply, :ok, datetime}

  def handle_call({:advance, duration}, _from, state) do
    new_state = apply_duration(state, duration)
    {:reply, :ok, new_state}
  end