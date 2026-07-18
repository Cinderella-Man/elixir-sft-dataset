  @impl true
  def handle_info({:task_finished, worker, ref, result}, state) do
    case Map.get(state.busy_workers, worker) do
      {^ref, client_pid} ->
        send(client_pid, {ref, :result, result})
        {:noreply, dispatch_next(state, worker)}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, mref, :process, pid, reason}, state) do
    new_monitors = Map.delete(state.monitors, mref)

    state =
      case Map.pop(state.busy_workers, pid) do
        {{ref, client_pid}, updated_busy} ->
          send(client_pid, {ref, :error, {:task_crashed, reason}})
          %{state | busy_workers: updated_busy}

        {nil, _} ->
          %{state | idle_workers: List.delete(state.idle_workers, pid)}
      end

    {:ok, new_pid} = start_worker(state.sup)
    new_mref = Process.monitor(new_pid)

    final_state = %{state | monitors: Map.put(new_monitors, new_mref, new_pid)}
    {:noreply, dispatch_next(final_state, new_pid)}
  end

  @impl true
  def handle_info(:promote_stale_tasks, state) do
    now = System.monotonic_time(:millisecond)
    threshold = state.promote_after_ms

    # Promote low → normal
    {promoted_from_low, remaining_low} =
      partition_stale(state.queues.low, now, threshold)

    # Promote normal → high
    {promoted_from_normal, remaining_normal} =
      partition_stale(state.queues.normal, now, threshold)

    # Merge promoted tasks into their target queues (append to back to keep FIFO among promoted)
    new_normal = enqueue_all(remaining_normal, promoted_from_low)
    new_high = enqueue_all(state.queues.high, promoted_from_normal)

    new_queues = %{high: new_high, normal: new_normal, low: remaining_low}

    schedule_promotion(threshold)
    {:noreply, %{state | queues: new_queues}}
  end