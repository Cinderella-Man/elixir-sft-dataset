defp peek_highest(queues) do
  case sorted_priorities(queues) do
    [] ->
      nil

    [priority | _rest] ->
      case :queue.peek(queues[priority]) do
        {:value, {_ref, task}} -> {task, priority}
        :empty -> nil
      end
  end
end