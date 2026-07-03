defp find_and_remove(queues, target_ref) do
  Enum.reduce_while(queues, :not_found, fn {priority, queue}, _acc ->
    items = :queue.to_list(queue)

    case Enum.split_with(items, fn {ref, _task} -> ref != target_ref end) do
      {remaining, [{^target_ref, _task}]} ->
        new_queue = :queue.from_list(remaining)
        updated_queues = Map.put(queues, priority, new_queue)
        {:halt, {:found, updated_queues}}

      {_all_items, []} ->
        {:cont, :not_found}
    end
  end)
end