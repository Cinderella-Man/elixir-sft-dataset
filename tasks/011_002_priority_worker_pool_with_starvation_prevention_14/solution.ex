  defp schedule_promotion(interval_ms) do
    Process.send_after(self(), :promote_stale_tasks, interval_ms)
  end