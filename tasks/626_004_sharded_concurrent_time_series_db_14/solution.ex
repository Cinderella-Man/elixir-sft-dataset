  defp schedule_cleanup(%{cleanup_interval_ms: :infinity}), do: :ok

  defp schedule_cleanup(%{cleanup_interval_ms: interval}) do
    Process.send_after(self(), :cleanup_tick, interval)
    :ok
  end