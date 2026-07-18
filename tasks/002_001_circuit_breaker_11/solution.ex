  @impl true
  def handle_call(:state, _from, state) do
    {:reply, state.circuit_state, state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, reset_to_closed(state)}
  end

  def handle_call({:call, func}, _from, state) do
    case state.circuit_state do
      :closed ->
        handle_closed(func, state)

      :open ->
        handle_open(func, state)

      :half_open ->
        handle_half_open(func, state)
    end
  end