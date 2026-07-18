  @impl GenServer
  def handle_info(:cleanup, state) do
    now = state.clock.()

    surviving_sessions =
      Map.filter(state.sessions, fn {_id, session} ->
        not expired?(session, now, state.timeout_ms)
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | sessions: surviving_sessions}}
  end

  # Catch-all for unexpected messages — keeps the process alive and logs.
  def handle_info(msg, state) do
    require Logger
    Logger.warning("#{__MODULE__} received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end