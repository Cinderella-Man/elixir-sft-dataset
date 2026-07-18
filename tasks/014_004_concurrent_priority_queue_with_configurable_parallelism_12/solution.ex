  @impl true
  def handle_info(:process_next, state) do
    if map_size(state.active_workers) >= state.max_concurrency do
      # All slots full — processing is re-triggered when a worker finishes.
      {:noreply, state}
    else
      case pop_highest(state.queues) do
        {nil, _queues} ->
          {:noreply, maybe_notify_drain(state)}

        {task, queues} ->
          parent = self()
          processor = state.processor

          {pid, ref} =
            spawn_monitor(fn ->
              result = processor.(task)
              send(parent, {:task_result, self(), result})
            end)

          active_workers = Map.put(state.active_workers, pid, {task, ref})

          new_state =
            %{state | queues: queues, active_workers: active_workers}
            |> maybe_trigger_processing()

          {:noreply, new_state}
      end
    end
  end

  def handle_info({:task_result, pid, result}, state) do
    if Map.has_key?(state.active_workers, pid) do
      # Store the result; it is finalized when the worker's :DOWN arrives.
      {:noreply, %{state | pending_results: Map.put(state.pending_results, pid, result)}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Map.pop(state.active_workers, pid) do
      {{task, ^ref}, remaining_workers} ->
        {result, pending_results} = Map.pop(state.pending_results, pid, @no_result)

        processed =
          case result do
            @no_result -> state.processed
            value -> [{task, value} | state.processed]
          end

        state =
          %{
            state
            | active_workers: remaining_workers,
              pending_results: pending_results,
              processed: processed
          }
          |> maybe_trigger_processing()
          |> maybe_notify_drain()

        {:noreply, state}

      {_other, _workers} ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}