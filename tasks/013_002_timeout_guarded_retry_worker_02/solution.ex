  defp launch_attempt(func, attempt, opts, from, state) do
    timeout = Keyword.get(opts, :attempt_timeout_ms, 5_000)

    # The timeout runs INSIDE the wrapper task, which owns the inner task
    # and may therefore yield to and shut it down; the server never blocks.
    # A crash in `func` kills the linked wrapper with the same reason, so
    # it surfaces at the server as this task's :DOWN — the
    # `{:task_crashed, reason}` path.
    task =
      Task.Supervisor.async_nolink(state.supervisor, fn ->
        inner = Task.async(fn -> func.() end)

        case Task.yield(inner, timeout) do
          {:ok, result} ->
            result

          nil ->
            _ = Task.shutdown(inner, :brutal_kill)
            {:error, :timeout}
        end
      end)

    record = %{from: from, func: func, attempt: attempt, opts: opts}
    %{state | tasks: Map.put(state.tasks, task.ref, record)}
  end