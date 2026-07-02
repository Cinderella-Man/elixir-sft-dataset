  @impl true
  def handle_info({:fire, key}, state) do
    case Map.pop(state, key) do
      {{_timer_ref, func}, new_state} ->
        # Run the func off the server's reduction path so a slow or crashing
        # func can't wedge the GenServer.
        spawn(fn -> func.() end)
        {:noreply, new_state}

      {nil, new_state} ->
        {:noreply, new_state}
    end
  end