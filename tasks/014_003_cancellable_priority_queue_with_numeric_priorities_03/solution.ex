  defp pop_highest(queues) do
    case sorted_priorities(queues) do
      [] ->
        {nil, queues}

      [priority | _rest] ->
        case :queue.out(queues[priority]) do
          {{:value, entry}, rest} ->
            {entry, Map.put(queues, priority, rest)}

          {:empty, _} ->
            {nil, queues}
        end
    end
  end