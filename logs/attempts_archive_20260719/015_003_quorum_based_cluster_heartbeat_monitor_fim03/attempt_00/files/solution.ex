  @impl true
  def handle_call({:register, name, check_funcs, interval_ms, opts}, _from, state) do
    total = length(check_funcs)
    quorum = Keyword.get(opts, :quorum, div(total, 2) + 1)
    notify = Keyword.get(opts, :notify, fn _name, _healthy -> :ok end)
    gen = make_ref()

    cluster = %{
      check_funcs: check_funcs,
      interval_ms: interval_ms,
      quorum: quorum,
      notify: notify,
      status: :up,
      healthy: total,
      total: total,
      gen: gen
    }

    Process.send_after(self(), {:poll, name, gen}, interval_ms)
    {:reply, :ok, put_in(state.clusters[name], cluster)}
  end

  def handle_call({:poll, name}, _from, state) do
    case Map.fetch(state.clusters, name) do
      {:ok, cluster} ->
        updated = run_poll(cluster, name)
        {:reply, {:ok, updated.status}, put_in(state.clusters[name], updated)}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:cluster_state, name}, _from, state) do
    case Map.fetch(state.clusters, name) do
      {:ok, cluster} ->
        view = %{status: cluster.status, healthy: cluster.healthy, total: cluster.total}
        {:reply, view, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:snapshot, _from, state) do
    view = Map.new(state.clusters, fn {name, cluster} -> {name, cluster.status} end)
    {:reply, view, state}
  end

  def handle_call({:unregister, name}, _from, state) do
    case Map.fetch(state.clusters, name) do
      {:ok, _cluster} ->
        {:reply, :ok, %{state | clusters: Map.delete(state.clusters, name)}}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end