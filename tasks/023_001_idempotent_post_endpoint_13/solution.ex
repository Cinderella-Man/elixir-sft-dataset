  defp schedule_cleanup(interval) do
    if interval != :infinity do
      Process.send_after(self(), :cleanup, interval)
    end
  end