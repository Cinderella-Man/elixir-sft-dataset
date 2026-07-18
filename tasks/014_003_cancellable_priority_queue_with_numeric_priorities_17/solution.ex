  defp clean_empty_queues(queues) do
    queues
    |> Enum.reject(fn {_priority, queue} -> :queue.is_empty(queue) end)
    |> Map.new()
  end