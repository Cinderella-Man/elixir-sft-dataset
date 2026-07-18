  @impl true
  def handle_call({:enqueue, task, priority}, _from, state) do
    ref = make_ref()
    entry = {ref, task}

    queue = Map.get(state.queues, priority, :queue.new())
    updated_queue = :queue.in(entry, queue)
    queues = Map.put(state.queues, priority, updated_queue)

    state =
      %{state | queues: queues}
      |> maybe_trigger_processing()

    {:reply, {:ok, ref}, state}
  end

  def handle_call({:cancel, ref}, _from, state) do
    case find_and_remove(state.queues, ref) do
      {:found, updated_queues} ->
        queues = clean_empty_queues(updated_queues)
        state = %{state | queues: queues, cancelled_count: state.cancelled_count + 1}
        {:reply, :ok, state}

      :not_found ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:status, _from, state) do
    by_priority =
      state.queues
      |> Enum.map(fn {priority, queue} -> {priority, :queue.len(queue)} end)
      |> Enum.filter(fn {_p, count} -> count > 0 end)
      |> Map.new()

    pending = Enum.reduce(by_priority, 0, fn {_p, count}, acc -> acc + count end)

    result = %{
      pending: pending,
      by_priority: by_priority,
      cancelled: state.cancelled_count
    }

    {:reply, result, state}
  end

  def handle_call(:peek, _from, state) do
    case peek_highest(state.queues) do
      nil ->
        {:reply, :empty, state}

      {task, priority} ->
        {:reply, {:ok, task, priority}, state}
    end
  end

  def handle_call(:processed, _from, state) do
    {:reply, Enum.reverse(state.processed), state}
  end

  def handle_call(:drain, from, state) do
    if queue_empty?(state) and not state.processing do
      {:reply, :ok, state}
    else
      {:noreply, %{state | drain_waiters: [from | state.drain_waiters]}}
    end
  end