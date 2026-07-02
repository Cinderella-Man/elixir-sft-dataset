defp put_queue(state, queue, entries) do
  queues =
    case entries do
      [] -> Map.delete(state.queues, queue)
      _ -> Map.put(state.queues, queue, entries)
    end

  %{state | queues: queues}
end