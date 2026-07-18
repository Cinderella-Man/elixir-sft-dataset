  defp try_steal(id, coordinator, process_fn, acc) do
    case find_victim(id, coordinator) do
      nil ->
        acc

      victim_id ->
        case steal_low_half(victim_id, coordinator) do
          [] ->
            try_steal(id, coordinator, process_fn, acc)

          stolen ->
            # `stolen` is a sorted-descending suffix; merge into our (empty or
            # residual) queue keeping descending order.
            Agent.update(coordinator, fn state ->
              Map.update(state, id, stolen, fn existing -> merge_desc(existing, stolen) end)
            end)

            process_local_queue(id, coordinator, process_fn, acc)
        end
    end
  end