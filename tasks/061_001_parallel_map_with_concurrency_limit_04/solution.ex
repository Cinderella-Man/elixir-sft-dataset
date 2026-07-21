  defp start_task(func, elem), do: Task.async(fn -> func.(elem) end)
