  defp steal_half(victim_id, coordinator) do
    Agent.get_and_update(coordinator, fn state ->
      queue = Map.fetch!(state, victim_id)
      len = length(queue)

      if len < 2 do
        # Not worth stealing a single item that the victim is about to take.
        {[], state}
      else
        steal_count = div(len, 2)
        keep_count = len - steal_count
        {keep, stolen} = Enum.split(queue, keep_count)
        {stolen, Map.put(state, victim_id, keep)}
      end
    end)
  end