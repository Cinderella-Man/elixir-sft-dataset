  # Return the id of the worker (other than `thief_id`) with the longest queue,
  # or `nil` if every other worker's queue is empty.
  @spec find_victim(non_neg_integer(), pid()) :: non_neg_integer() | nil
  defp find_victim(thief_id, coordinator) do
    Agent.get(coordinator, fn state ->
      state
      # A queue needs at least TWO items to be worth targeting — steal_half
      # refuses single-item queues, so selecting one would spin through a
      # fruitless find/steal loop (hot-looping on the Agent) for as long as
      # the victim stays busy inside process_fn.
      |> Enum.reject(fn {id, queue} ->
        id == thief_id or match?([], queue) or match?([_], queue)
      end)
      |> case do
        [] ->
          nil

        candidates ->
          {victim_id, _queue} = Enum.max_by(candidates, fn {_id, q} -> length(q) end)
          victim_id
      end
    end)
  end