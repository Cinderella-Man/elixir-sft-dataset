  @impl true
  def handle_info({:check, name, token}, state) do
    case Map.fetch(state, name) do
      {:ok, %{token: ^token} = probe} ->
        updated = run_check(name, probe)
        Process.send_after(self(), {:check, name, token}, probe.interval_ms)
        {:noreply, Map.put(state, name, updated)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end