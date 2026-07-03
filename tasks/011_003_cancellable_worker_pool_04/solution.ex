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
          was_cancelled = MapSet.member?(state.cancelled_refs, ref)

          if was_cancelled do
            # Already sent :cancelled in the cancel handler, just clean up
            %{
              state
              | busy_workers: updated_busy,
                cancelled_refs: MapSet.delete(state.cancelled_refs, ref)
            }
          else
            # Genuine crash — notify client
            send(client_pid, {ref, :error, {:task_crashed, reason}})
            %{state | busy_workers: updated_busy}
          end

        {nil, _} ->
          %{state | idle_workers: List.delete(state.idle_workers, pid)}
      end

    # Replace the dead worker
    {:ok, new_pid} = start_worker(state.sup)
    new_mref = Process.monitor(new_pid)

    final_state = %{state | monitors: Map.put(new_monitors, new_mref, new_pid)}
    {:noreply, dispatch_next(final_state, new_pid)}
  end