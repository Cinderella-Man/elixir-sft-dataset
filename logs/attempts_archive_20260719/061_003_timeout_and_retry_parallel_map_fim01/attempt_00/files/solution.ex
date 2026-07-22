  defp loop(running, queue, _cfg, results) when map_size(running) == 0 and queue == [] do
    results
  end

  defp loop(running, queue, cfg, results) do
    receive do
      {ref, {:ok, value}} when is_map_key(running, ref) ->
        {_pid, mon, idx, _elem, _al, timer} = Map.fetch!(running, ref)
        cleanup(mon, timer)
        running = Map.delete(running, ref)
        results = Map.put(results, idx, {:ok, value})
        {running, queue} = fill(running, queue, cfg)
        loop(running, queue, cfg, results)

      {ref, {:error, reason}} when is_map_key(running, ref) ->
        {_pid, mon, idx, _elem, _al, timer} = Map.fetch!(running, ref)
        cleanup(mon, timer)
        running = Map.delete(running, ref)
        results = Map.put(results, idx, {:error, reason})
        {running, queue} = fill(running, queue, cfg)
        loop(running, queue, cfg, results)

      {:timeout, ref} when is_map_key(running, ref) ->
        {pid, mon, idx, elem, attempts_left, timer} = Map.fetch!(running, ref)
        cleanup(mon, timer)
        Process.exit(pid, :kill)
        drain(ref)
        running = Map.delete(running, ref)
        remaining = attempts_left - 1

        if remaining > 0 do
          {r, entry} = start_attempt(self(), cfg.func, elem, idx, remaining, cfg.timeout)
          loop(Map.put(running, r, entry), queue, cfg, results)
        else
          results = Map.put(results, idx, {:error, :timeout})
          {running, queue} = fill(running, queue, cfg)
          loop(running, queue, cfg, results)
        end

      {:DOWN, mon, :process, _pid, reason} ->
        case Enum.find(running, fn {_r, {_p, m, _i, _e, _a, _t}} -> m == mon end) do
          {ref, {_pid, _mon, idx, _elem, _al, timer}} ->
            Process.cancel_timer(timer)
            drain(ref)
            running = Map.delete(running, ref)
            results = Map.put(results, idx, {:error, {:down, reason}})
            {running, queue} = fill(running, queue, cfg)
            loop(running, queue, cfg, results)

          nil ->
            loop(running, queue, cfg, results)
        end

      _other ->
        loop(running, queue, cfg, results)
    end
  end