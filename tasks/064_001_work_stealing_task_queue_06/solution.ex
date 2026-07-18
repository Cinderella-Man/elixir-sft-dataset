  # Process items from this worker's own queue until it is empty, then try to
  # steal.  Using an accumulator keeps the recursion stack-friendly.
  defp process_local_queue(id, coordinator, process_fn, acc) do
    case pop_item(id, coordinator) do
      {:ok, item} ->
        result = process_fn.(item)
        entry = %{item: item, result: result, worker_id: id}
        process_local_queue(id, coordinator, process_fn, [entry | acc])

      :empty ->
        try_steal(id, coordinator, process_fn, acc)
    end
  end