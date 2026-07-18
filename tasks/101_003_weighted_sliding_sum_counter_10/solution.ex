  @impl true
  def handle_info(:cleanup, state) do
    {:noreply, state |> cleanup() |> schedule_cleanup()}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end