  @impl true
  def handle_call({:enqueue, task, priority, opts}, _from, state) do
    ttl_ms = Keyword.get(opts, :ttl_ms, state.default_ttl_ms)
    now = state.clock.()
    expires_at = now + ttl_ms

    entry = {task, expires_at}
    updated_queue = :queue.in(entry, state.queues[priority])
    queues = Map.put(state.queues, priority, updated_queue)

    state =
      %{state | queues: queues}
      |> maybe_trigger_processing()

    {:reply, :ok, state}
  end

  def handle_call(:status, _from, state) do
    now = state.clock.()

    counts =
      Enum.reduce([:high, :normal, :low], %{}, fn priority, acc ->
        count =
          state.queues[priority]
          |> :queue.to_list()
          |> Enum.count(fn {_task, expires_at} -> expires_at > now end)

        Map.put(acc, priority, count)
      end)

    counts = Map.put(counts, :expired, length(state.expired))

    {:reply, counts, state}
  end

  def handle_call(:processed, _from, state) do
    {:reply, Enum.reverse(state.processed), state}
  end

  def handle_call(:expired, _from, state) do
    {:reply, Enum.reverse(state.expired), state}
  end

  def handle_call(:drain, from, state) do
    if queue_empty?(state) and not state.processing do
      {:reply, :ok, state}
    else
      {:noreply, %{state | drain_waiters: [from | state.drain_waiters]}}
    end
  end