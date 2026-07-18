  defp queue_empty?(state) do
    Enum.all?([:high, :normal, :low], fn p -> :queue.is_empty(state.queues[p]) end)
  end