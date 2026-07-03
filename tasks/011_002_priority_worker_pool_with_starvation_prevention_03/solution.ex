  defp dequeue_highest(queues) do
    Enum.reduce_while([:high, :normal, :low], :empty, fn priority, _acc ->
      case :queue.out(queues[priority]) do
        {{:value, task}, remaining} ->
          {:halt, {:ok, task, Map.put(queues, priority, remaining)}}

        {:empty, _} ->
          {:cont, :empty}
      end
    end)
  end