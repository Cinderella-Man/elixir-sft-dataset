  defp handle_task_result(result, func, attempt, opts, from, state) do
    {_, new_state} = handle_task_result_sync(result, func, attempt, opts, from, state)
    {:noreply, new_state}
  end