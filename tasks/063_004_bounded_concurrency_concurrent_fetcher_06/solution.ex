  # Waits for one worker message. The guards make sure only messages belonging
  # to this pool are consumed — unrelated mail in the caller's inbox is left
  # untouched.
  defp collect(pending, running, results, max, deadline, remaining) do
    receive do
      {:fetch_result, pid, reply} when is_map_key(running, pid) ->
        {ref, name} = Map.fetch!(running, pid)
        Process.demonitor(ref, [:flush])
        loop(pending, Map.delete(running, pid), Map.put(results, name, reply), max, deadline)

      {:DOWN, _ref, :process, pid, reason} when is_map_key(running, pid) ->
        {_ref, name} = Map.fetch!(running, pid)

        loop(
          pending,
          Map.delete(running, pid),
          Map.put(results, name, {:error, reason}),
          max,
          deadline
        )
    after
      remaining ->
        finalize_timeout(pending, running, results)
    end
  end