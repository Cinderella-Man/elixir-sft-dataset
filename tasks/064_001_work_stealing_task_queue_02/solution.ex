  # When the local queue is empty, look for the busiest other worker and steal
  # half its remaining items.  If no work exists anywhere, we are done.
  defp try_steal(id, coordinator, process_fn, acc) do
    case find_victim(id, coordinator) do
      nil ->
        # No other worker has any remaining work — we are finished.
        acc

      victim_id ->
        case steal_half(victim_id, coordinator) do
          [] ->
            # The victim emptied its queue between the time we identified it
            # and the time we tried to steal.  Try again with a fresh scan.
            try_steal(id, coordinator, process_fn, acc)

          stolen ->
            # Deposit the stolen items into our own queue and resume normal
            # processing.  Prepend so we work through them immediately.
            Agent.update(coordinator, fn state ->
              Map.update(state, id, stolen, fn existing -> stolen ++ existing end)
            end)

            process_local_queue(id, coordinator, process_fn, acc)
        end
    end
  end