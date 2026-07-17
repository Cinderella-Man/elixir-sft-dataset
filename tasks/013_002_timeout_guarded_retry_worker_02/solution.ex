  defp launch_attempt(func, attempt, opts, from, state) do
    timeout = Keyword.get(opts, :attempt_timeout_ms, 5_000)

    task = Task.Supervisor.async_nolink(state.supervisor, fn -> func.() end)

    outcome =
      case Task.yield(task, timeout) do
        {:ok, result} ->
          result

        {:exit, reason} ->
          {:error, {:task_crashed, reason}}

        nil ->
          _ = Task.shutdown(task, :brutal_kill)
          {:error, :timeout}
      end

    {_, state} = handle_task_result_sync(outcome, func, attempt, opts, from, state)
    state
  end