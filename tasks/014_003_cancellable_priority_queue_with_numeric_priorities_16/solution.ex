  defp sorted_priorities(queues) do
    queues
    |> Map.keys()
    |> Enum.filter(fn p -> not :queue.is_empty(queues[p]) end)
    |> Enum.sort()
  end