  defp steal_phase(id, coordinator, process_fn, batch, acc) do
    case find_victim(id, coordinator) do
      nil ->
        acc

      victim_id ->
        case steal(victim_id, coordinator, batch) do
          [] ->
            # Victim emptied before we could take anything; a skipped steal must
            # not count toward the metric. Re-scan.
            steal_phase(id, coordinator, process_fn, batch, acc)

          stolen ->
            Agent.update(coordinator, fn state ->
              Map.update(state, id, stolen, fn existing -> stolen ++ existing end)
            end)

            acc = %{acc | steals: acc.steals + 1, stolen: acc.stolen + length(stolen)}
            loop(id, coordinator, process_fn, batch, acc)
        end
    end
  end