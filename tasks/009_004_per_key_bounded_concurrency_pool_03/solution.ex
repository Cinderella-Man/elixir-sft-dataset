  @impl GenServer
  def handle_info({:task_done, key, ref, result}, state) do
    case Map.fetch(state.keys, key) do
      {:ok, key_state} ->
        # Find the caller for this task and reply
        {from, new_tasks} = Map.pop(key_state.tasks, ref)

        if from do
          GenServer.reply(from, result)
        end

        new_key_state = %{key_state | running: key_state.running - 1, tasks: new_tasks}

        # Start the next queued caller if any
        new_key_state = maybe_start_next(key, new_key_state)

        # Clean up the key if completely idle
        if new_key_state.running == 0 and new_key_state.queue == [] do
          {:noreply, %{state | keys: Map.delete(state.keys, key)}}
        else
          {:noreply, put_key_state(state, key, new_key_state)}
        end

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end