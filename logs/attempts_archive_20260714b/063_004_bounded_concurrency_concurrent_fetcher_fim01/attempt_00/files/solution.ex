  # Kills every live fetch and marks both running and still-queued sources as
  # timed out.
  defp finalize_timeout(pending, running, ref_to_task, results) do
    Enum.each(ref_to_task, fn {_ref, task} -> Task.shutdown(task, :brutal_kill) end)

    results =
      Enum.reduce(running, results, fn {_ref, name}, acc ->
        Map.put(acc, name, {:error, :timeout})
      end)

    Enum.reduce(pending, results, fn {name, _fetch_fn}, acc ->
      Map.put(acc, name, {:error, :timeout})
    end)
  end