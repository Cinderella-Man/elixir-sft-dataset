  defp queue_empty?(state) do
    Enum.all?(state.queues, fn {_p, queue} -> :queue.is_empty(queue) end)
  end