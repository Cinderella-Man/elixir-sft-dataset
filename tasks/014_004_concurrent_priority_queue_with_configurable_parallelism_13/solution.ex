  defp queue_empty?(state) do
    Enum.all?(@priority_order, fn p -> :queue.is_empty(state.queues[p]) end)
  end