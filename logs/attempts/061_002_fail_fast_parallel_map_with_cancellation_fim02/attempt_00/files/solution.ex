  # Kill every still-running task and discard any messages they may have sent.
  defp cancel_all(running) do
    Enum.each(running, fn {ref, {pid, mon, _idx}} ->
      Process.demonitor(mon, [:flush])
      Process.exit(pid, :kill)

      receive do
        {^ref, _} -> :ok
      after
        0 -> :ok
      end
    end)

    :ok
  end