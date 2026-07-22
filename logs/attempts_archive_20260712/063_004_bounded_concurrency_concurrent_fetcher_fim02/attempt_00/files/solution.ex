  # Starts queued fetches until the pool is full or the queue is empty.
  defp fill(pending, running, ref_to_task, max) do
    if pending == [] or map_size(running) >= max do
      {pending, running, ref_to_task}
    else
      [{name, fetch_fn} | rest] = pending
      task = Task.async(fn -> safe_call(fetch_fn) end)
      fill(rest, Map.put(running, task.ref, name), Map.put(ref_to_task, task.ref, task), max)
    end
  end