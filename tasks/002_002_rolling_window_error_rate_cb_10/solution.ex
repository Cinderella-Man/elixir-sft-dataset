  @impl true
  def handle_call({:call, func}, _from, state) do
    state = maybe_expire_open(state)

    case state.state do
      :closed ->
        {reply, new_state} = execute_in_closed(state, func)
        {:reply, reply, new_state}

      :open ->
        {:reply, {:error, :circuit_open}, state}

      :half_open ->
        if state.probes_in_flight < state.config.half_open_max_probes do
          state = %{state | probes_in_flight: state.probes_in_flight + 1}
          {reply, new_state} = execute_in_half_open(state, func)
          {:reply, reply, new_state}
        else
          {:reply, {:error, :circuit_open}, state}
        end
    end
  end

  def handle_call(:get_state, _from, state) do
    state = maybe_expire_open(state)
    {:reply, state.state, state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | state: :closed, outcomes: [], opened_at: nil, probes_in_flight: 0}}
  end