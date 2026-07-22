  # Take up to `batch` items from the back of the victim's queue.
  @spec steal(non_neg_integer(), pid(), :half | pos_integer()) :: list()
  defp steal(victim_id, coordinator, batch) do
    Agent.get_and_update(coordinator, fn state ->
      queue = Map.fetch!(state, victim_id)
      len = length(queue)

      if len == 0 do
        {[], state}
      else
        steal_count = min(batch_size(batch, len), len)
        keep_count = len - steal_count
        {keep, stolen} = Enum.split(queue, keep_count)
        {stolen, Map.put(state, victim_id, keep)}
      end
    end)
  end