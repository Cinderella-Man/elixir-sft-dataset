  @impl true
  def handle_call({:enqueue, task, priority}, _from, state) do
    updated_queue = :queue.in(task, state.queues[priority])
    queues = Map.put(state.queues, priority, updated_queue)

    state =
      %{state | queues: queues}
      |> maybe_trigger_processing()

    {:reply, :ok, state}
  end

  def handle_call(:status, _from, state) do
    counts = %{
      critical: :queue.len(state.queues.critical),
      normal: :queue.len(state.queues.normal),
      low: :queue.len(state.queues.low),
      active: map_size(state.active_workers),
      max_concurrency: state.max_concurrency
    }

    {:reply, counts, state}
  end

  def handle_call(:processed, _from, state) do
    {:reply, Enum.reverse(state.processed), state}
  end

  def handle_call(:drain, from, state) do
    if queue_empty?(state) and map_size(state.active_workers) == 0 do
      {:reply, :ok, state}
    else
      {:noreply, %{state | drain_waiters: [from | state.drain_waiters]}}
    end
  end