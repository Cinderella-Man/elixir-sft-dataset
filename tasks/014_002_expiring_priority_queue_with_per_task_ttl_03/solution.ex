  defp pop_highest(queues) do
    Enum.find_value([:high, :normal, :low], {nil, queues}, fn priority ->
      case :queue.out(queues[priority]) do
        {{:value, entry}, rest} -> {entry, Map.put(queues, priority, rest), priority}
        {:empty, _} -> nil
      end
    end)
  end