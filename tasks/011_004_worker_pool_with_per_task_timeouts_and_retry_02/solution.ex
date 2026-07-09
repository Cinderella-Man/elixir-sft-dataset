  defp handle_task_failure(state, task_info, failure_type) do
    new_attempts = task_info.attempts

    if new_attempts <= task_info.max_retries do
      # Retry: re-enqueue at front of queue
      updated_task = task_info

      # Start replacement worker
      {:ok, new_pid} = start_worker(state.sup)
      new_mref = Process.monitor(new_pid)

      state = %{
        state
        | monitors: Map.put(state.monitors, new_mref, new_pid),
          queue: :queue.in_r(updated_task, state.queue),
          retry_count: state.retry_count + 1
      }

      {:noreply, make_worker_available(state, new_pid)}
    else
      # Exhausted retries — notify client
      error =
        case failure_type do
          :task_timeout -> {:task_timeout, new_attempts}
          {:task_failed, reason} -> {:task_failed, reason, new_attempts}
        end

      send(task_info.client_pid, {task_info.ref, :error, error})

      {:ok, new_pid} = start_worker(state.sup)
      new_mref = Process.monitor(new_pid)

      state = %{state | monitors: Map.put(state.monitors, new_mref, new_pid)}
      {:noreply, make_worker_available(state, new_pid)}
    end
  end