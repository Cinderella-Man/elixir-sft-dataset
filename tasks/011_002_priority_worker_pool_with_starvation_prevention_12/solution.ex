  defp total_queue_length(state) do
    state.queues
    |> Map.values()
    |> Enum.map(&:queue.len/1)
    |> Enum.sum()
  end