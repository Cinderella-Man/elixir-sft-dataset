  # Kills every live fetch, waits for confirmation that it is gone, discards any
  # late result it may have sent, and marks running plus still-queued sources as
  # timed out.
  defp finalize_timeout(pending, running, results) do
    results =
      Enum.reduce(running, results, fn {pid, {ref, name}}, acc ->
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
        end

        receive do
          {:fetch_result, ^pid, _reply} -> :ok
        after
          0 -> :ok
        end

        Map.put(acc, name, {:error, :timeout})
      end)

    Enum.reduce(pending, results, fn {name, _fetch_fn}, acc ->
      Map.put(acc, name, {:error, :timeout})
    end)
  end