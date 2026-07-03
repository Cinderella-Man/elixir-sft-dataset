  defp launch_attempt(func, attempt, opts, from, state) do
    timeout = Keyword.get(opts, :attempt_timeout_ms, 5_000)

    task = Task.async(fn -> func.() end)

    case Task.yield(task, timeout) do
      {:ok, result} ->
        # Completed within timeout — handle synchronously
        Process.demonitor(task.ref, [:flush])
        {_, state} = handle_task_result_sync(result, func, attempt, opts, from, state)
        state

      nil ->
        # Timed out — shut it down
        Task.shutdown(task, :brutal_kill)
        {_, state} = handle_task_result_sync({:error, :timeout}, func, attempt, opts, from, state)
        state
    end
  end