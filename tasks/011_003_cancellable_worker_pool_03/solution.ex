@impl true
def handle_call({:submit, task_func}, {from_pid, _}, state) do
  ref = make_ref()
  task = {ref, from_pid, task_func}

  cond do
    length(state.idle_workers) > 0 ->
      [worker | rest] = state.idle_workers
      send(worker, {:run, task})

      new_state = %{
        state
        | idle_workers: rest,
          busy_workers: Map.put(state.busy_workers, worker, {ref, from_pid})
      }

      {:reply, {:ok, ref}, new_state}

    :queue.len(state.queue) < state.max_queue ->
      new_state = %{
        state
        | queue: :queue.in(task, state.queue),
          pending_refs: Map.put(state.pending_refs, ref, from_pid)
      }

      {:reply, {:ok, ref}, new_state}

    true ->
      {:reply, {:error, :queue_full}, state}
  end
end

@impl true
def handle_call({:cancel, ref}, _from, state) do
  # Case 1: Task is in the queue (pending)
  case Map.pop(state.pending_refs, ref) do
    {client_pid, remaining_pending} when not is_nil(client_pid) ->
      new_queue = queue_remove(state.queue, ref)
      send(client_pid, {ref, :error, :cancelled})

      new_state = %{
        state
        | queue: new_queue,
          pending_refs: remaining_pending,
          cancelled_count: state.cancelled_count + 1
      }

      {:reply, :ok, new_state}

    {nil, _} ->
      # Case 2: Task is currently running on a worker
      case find_busy_worker(state.busy_workers, ref) do
        {worker_pid, {^ref, client_pid}} ->
          # Mark this ref as cancelled so the :DOWN handler knows
          new_cancelled = MapSet.put(state.cancelled_refs, ref)
          # Kill the worker — this will trigger :DOWN
          Process.exit(worker_pid, :kill)

          # Send cancelled message to the client
          send(client_pid, {ref, :error, :cancelled})

          new_state = %{
            state
            | cancelled_refs: new_cancelled,
              cancelled_count: state.cancelled_count + 1
          }

          {:reply, :ok, new_state}

        nil ->
          # Case 3: Unknown ref
          {:reply, {:error, :not_found}, state}
      end
  end
end

@impl true
def handle_call(:status, _from, state) do
  status = %{
    busy_workers: map_size(state.busy_workers),
    idle_workers: length(state.idle_workers),
    queue_length: :queue.len(state.queue),
    cancelled_count: state.cancelled_count
  }

  {:reply, status, state}
end