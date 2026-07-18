  @impl true
  def handle_info(:process_next, state) do
    case pop_next_valid(state) do
      {:empty, state} ->
        state = %{state | processing: false} |> notify_drain_waiters()
        {:noreply, state}

      {:ok, task, state} ->
        parent = self()
        processor = state.processor

        {pid, ref} =
          spawn_monitor(fn ->
            result = processor.(task)
            send(parent, {:task_result, self(), result})
          end)

        new_state = %{
          state
          | current_task: task,
            current_ref: {pid, ref}
        }

        {:noreply, new_state}
    end
  end

  def handle_info({:task_result, pid, result}, %{current_ref: {pid, _ref}} = state) do
    state = %{state | processed: [{state.current_task, result} | state.processed]}
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, _}, %{current_ref: {pid, ref}} = state) do
    state = %{state | current_task: nil, current_ref: nil}

    if queue_empty?(state) do
      state = %{state | processing: false} |> notify_drain_waiters()
      {:noreply, state}
    else
      send(self(), :process_next)
      {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}