  @impl true
  def handle_info({:task_finished, worker, ref, result}, state) do
    case Map.get(state.busy_workers, worker) do
      %TaskInfo{ref: ^ref} = task_info ->
        send(task_info.client_pid, {ref, :result, result})
        state = cancel_task_timer(state, worker)
        {:noreply, make_worker_available(state, worker)}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:task_timeout, worker_pid}, state) do
    case Map.get(state.busy_workers, worker_pid) do
      %TaskInfo{} = task_info ->
        # Kill the worker
        Process.exit(worker_pid, :kill)

        state = cancel_task_timer(state, worker_pid)

        # The :DOWN handler will handle replacement and retry/failure
        # But we need to mark this as a timeout, not a crash
        # We do this by storing the timeout info before the :DOWN arrives
        busy = Map.put(state.busy_workers, worker_pid, {:timed_out, task_info})
        {:noreply, %{state | busy_workers: busy}}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, mref, :process, pid, reason}, state) do
    new_monitors = Map.delete(state.monitors, mref)
    state = %{state | monitors: new_monitors}

    case Map.pop(state.busy_workers, pid) do
      {{:timed_out, task_info}, updated_busy} ->
        # Timeout-triggered kill
        state = %{state | busy_workers: updated_busy}
        state = cancel_task_timer(state, pid)
        handle_task_failure(state, task_info, :task_timeout)

      {%TaskInfo{} = task_info, updated_busy} ->
        # Genuine crash
        state = %{state | busy_workers: updated_busy}
        state = cancel_task_timer(state, pid)
        handle_task_failure(state, task_info, {:task_failed, reason})

      {nil, _} ->
        # Idle worker died somehow
        state = %{state | idle_workers: List.delete(state.idle_workers, pid)}
        {:ok, new_pid} = start_worker(state.sup)
        new_mref = Process.monitor(new_pid)

        final_state = %{state | monitors: Map.put(state.monitors, new_mref, new_pid)}
        {:noreply, make_worker_available(final_state, new_pid)}
    end
  end