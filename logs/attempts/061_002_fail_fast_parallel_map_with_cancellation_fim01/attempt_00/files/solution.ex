  # All tasks accounted for and none failed.
  defp loop(running, _queue, _func, _parent, results) when map_size(running) == 0 do
    {:ok, order_results(results)}
  end

  defp loop(running, queue, func, parent, results) do
    receive do
      {ref, {:ok, value}} when is_map_key(running, ref) ->
        {_pid, mon, idx} = Map.fetch!(running, ref)
        Process.demonitor(mon, [:flush])
        running = Map.delete(running, ref)
        results = Map.put(results, idx, value)

        {running, queue} =
          case queue do
            [] ->
              {running, []}

            [{elem, i} | rest] ->
              {r, pid, m} = spawn_task(parent, func, elem)
              {Map.put(running, r, {pid, m, i}), rest}
          end

        loop(running, queue, func, parent, results)

      {ref, {:error, reason}} when is_map_key(running, ref) ->
        {_pid, mon, idx} = Map.fetch!(running, ref)
        Process.demonitor(mon, [:flush])
        cancel_all(Map.delete(running, ref))
        {:error, {idx, reason}}

      {:DOWN, mon, :process, _pid, reason} ->
        case Enum.find(running, fn {_ref, {_pid, m, _idx}} -> m == mon end) do
          {ref, {_pid, _mon, idx}} ->
            cancel_all(Map.delete(running, ref))
            {:error, {idx, reason}}

          nil ->
            loop(running, queue, func, parent, results)
        end

      _other ->
        loop(running, queue, func, parent, results)
    end
  end