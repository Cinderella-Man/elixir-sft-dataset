  @impl GenServer
  def handle_call({:execute, key, func}, from, state) do
    key_state = Map.get(state.keys, key, empty_key_state())

    if key_state.running < state.max_concurrency do
      # Slot available — start immediately
      new_key_state = start_task(key, func, from, key_state)
      {:noreply, put_key_state(state, key, new_key_state)}
    else
      # No slot — queue the caller
      new_key_state = %{key_state | queue: key_state.queue ++ [{from, func}]}
      {:noreply, put_key_state(state, key, new_key_state)}
    end
  end

  def handle_call({:status, key}, _from, state) do
    key_state = Map.get(state.keys, key, empty_key_state())

    reply = %{
      running: key_state.running,
      queued: length(key_state.queue)
    }

    {:reply, reply, state}
  end