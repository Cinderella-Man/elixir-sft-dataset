  # Base case: nothing running and nothing queued.
  defp collect(running, _queue = [], _func, _parent, results)
       when map_size(running) == 0,
       do: results

  defp collect(running, queue, func, parent, results) do
    {finished_ref, finished_idx, outcome} = await_one(running)

    new_results = Map.put(results, finished_idx, outcome)
    new_running = Map.delete(running, finished_ref)

    # Fill the freed slot immediately.
    {new_running, new_queue} =
      case queue do
        [] ->
          {new_running, []}

        [{elem, idx} | rest] ->
          {our_ref, mon_ref} = spawn_task(parent, func, elem)
          {Map.put(new_running, our_ref, {mon_ref, idx}), rest}
      end

    collect(new_running, new_queue, func, parent, new_results)
  end