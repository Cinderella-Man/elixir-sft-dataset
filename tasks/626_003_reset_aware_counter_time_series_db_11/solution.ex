  @impl true
  def handle_info(:cleanup, state) do
    new_state = cleanup(state)
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, new_state}
  end

  def handle_info(_msg, state), do: {:noreply, state}