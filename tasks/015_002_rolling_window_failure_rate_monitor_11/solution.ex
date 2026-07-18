  @impl GenServer
  def handle_call({:register, name, check_func, interval_ms, opts}, _from, state) do
    if Map.has_key?(state.services, name) do
      {:reply, {:error, :already_registered}, state}
    else
      window_size = Keyword.get(opts, :window_size, 5)
      threshold = Keyword.get(opts, :threshold, 0.6)

      service = %{
        check_func: check_func,
        interval_ms: interval_ms,
        window_size: window_size,
        threshold: threshold,
        status: :pending,
        last_check_at: nil,
        history: [],
        notified_down: false
      }

      schedule_check(name, interval_ms)

      {:reply, :ok, put_in(state.services[name], service)}
    end
  end

  def handle_call({:status, name}, _from, state) do
    case Map.fetch(state.services, name) do
      {:ok, service} -> {:reply, {:ok, to_status_info(service)}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:statuses, _from, state) do
    result = Map.new(state.services, fn {name, svc} -> {name, to_status_info(svc)} end)
    {:reply, result, state}
  end

  def handle_call({:deregister, name}, _from, state) do
    {:reply, :ok, %{state | services: Map.delete(state.services, name)}}
  end