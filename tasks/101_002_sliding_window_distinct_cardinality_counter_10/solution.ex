  @impl true
  def handle_info(:cleanup, state) do
    state = purge_expired(state)
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end