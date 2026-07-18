  defp try_steal(id, coordinator, process_fn, acc) do
    case find_victim(id, coordinator) do
      nil ->
        acc

      victim_id ->
        case steal_half(victim_id, coordinator) do
          [] ->
            try_steal(id, coordinator, process_fn, acc)

          stolen ->
            Agent.update(coordinator, fn state ->
              Map.update(state, id, stolen, fn existing -> stolen ++ existing end)
            end)

            process_local_queue(id, coordinator, process_fn, acc)
        end
    end
  end