  @impl true
  def handle_call({:submit, task_func, priority}, {from_pid, _}, state) do
    ref = make_ref()
    now = System.monotonic_time(:millisecond)
    task = {ref, from_pid, task_func, now}

    cond do
      length(state.idle_workers) > 0 ->
        [worker | rest] = state.idle_workers
        send(worker, {:run, {ref, from_pid, task_func}})

        new_state = %{
          state
          | idle_workers: rest,
            busy_workers: Map.put(state.busy_workers, worker, {ref, from_pid})
        }

        {:reply, {:ok, ref}, new_state}

      total_queue_length(state) < state.max_queue ->
        updated_queues =
          Map.update!(state.queues, priority, fn q -> :queue.in(task, q) end)

        {:reply, {:ok, ref}, %{state | queues: updated_queues}}

      true ->
        {:reply, {:error, :queue_full}, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      busy_workers: map_size(state.busy_workers),
      idle_workers: length(state.idle_workers),
      queue_high: :queue.len(state.queues.high),
      queue_normal: :queue.len(state.queues.normal),
      queue_low: :queue.len(state.queues.low),
      total_queue_length: total_queue_length(state)
    }

    {:reply, status, state}
  end