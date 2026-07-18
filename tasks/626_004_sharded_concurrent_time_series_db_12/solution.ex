  @impl true
  def handle_info(:cleanup_tick, state) do
    do_cleanup(state)
    schedule_cleanup(state)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end