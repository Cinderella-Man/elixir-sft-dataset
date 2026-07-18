  @impl GenServer
  def handle_info(:cleanup, state) do
    now = state.clock.()

    surviving_tokens =
      Map.filter(state.tokens, fn {_id, token} ->
        not expired?(token, now)
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | tokens: surviving_tokens}}
  end

  def handle_info(msg, state) do
    require Logger
    Logger.warning("#{__MODULE__} received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end