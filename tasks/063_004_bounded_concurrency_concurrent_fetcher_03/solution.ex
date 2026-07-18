  # Starts queued fetches until the pool is full or the queue is empty.
  defp fill(pending, running, max) do
    if pending == [] or map_size(running) >= max do
      {pending, running}
    else
      [{name, fetch_fn} | rest] = pending
      parent = self()

      {pid, ref} =
        spawn_monitor(fn -> send(parent, {:fetch_result, self(), safe_call(fetch_fn)}) end)

      fill(rest, Map.put(running, pid, {ref, name}), max)
    end
  end