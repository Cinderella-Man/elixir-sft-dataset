  @impl true
  def handle_call({:register, name, func, interval, opts}, _from, state) do
    generation = make_ref()
    threshold = Keyword.get(opts, :threshold, 3)
    notify = Keyword.get(opts, :notify, fn _name, _reason -> :ok end)

    service = %{
      check_func: func,
      interval_ms: interval,
      threshold: threshold,
      notify: notify,
      status: :up,
      failures: 0,
      generation: generation
    }

    schedule(name, generation, interval)
    {:reply, :ok, Map.put(state, name, service)}
  end

  def handle_call({:status, name}, _from, state) do
    case Map.get(state, name) do
      nil -> {:reply, {:error, :not_found}, state}
      service -> {:reply, service.status, state}
    end
  end

  def handle_call(:statuses, _from, state) do
    result = Map.new(state, fn {name, service} -> {name, service.status} end)
    {:reply, result, state}
  end

  def handle_call({:check_now, name}, _from, state) do
    case Map.get(state, name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      service ->
        {updated, status} = run_check(service, name)
        {:reply, {:ok, status}, Map.put(state, name, updated)}
    end
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end