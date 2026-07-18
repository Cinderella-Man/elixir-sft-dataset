  defp schedule_cleanup(%{cleanup_interval_ms: :infinity}), do: :ok

  defp schedule_cleanup(%{cleanup_interval_ms: interval_ms}) do
    Process.send_after(self(), :cleanup, interval_ms)
  end