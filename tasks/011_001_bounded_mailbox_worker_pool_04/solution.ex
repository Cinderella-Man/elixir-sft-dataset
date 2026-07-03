  @impl true
  def handle_call({:submit, task_func}, {from_pid, _}, state) do
    ref = make_ref()
    task = {ref, from_pid, task_func}

    cond do
      # Case 1: Instant dispatch to idle worker
      length(state.idle_workers) > 0 ->
        [worker | rest] = state.idle_workers
        send(worker, {:run, task})

        new_state = %{state |
          idle_workers: rest,
          busy_workers: Map.put(state.busy_workers, worker, {ref, from_pid})
        }
        {:reply, {:ok, ref}, new_state}

      # Case 2: Enqueue if there is room
      :queue.len(state.queue) < state.max_queue ->
        new_state = %{state | queue: :queue.in(task, state.queue)}
        {:reply, {:ok, ref}, new_state}

      # Case 3: Queue full
      true ->
        {:reply, {:error, :queue_full}, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      busy_workers: map_size(state.busy_workers),
      idle_workers: length(state.idle_workers),
      queue_length: :queue.len(state.queue)
    }
    {:reply, status, state}
  end