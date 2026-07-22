  @impl true
  def handle_info({:poll, name, gen}, state) do
    case Map.fetch(state.clusters, name) do
      {:ok, %{gen: ^gen} = cluster} ->
        updated = run_poll(cluster, name)
        Process.send_after(self(), {:poll, name, gen}, cluster.interval_ms)
        {:noreply, put_in(state.clusters[name], updated)}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end