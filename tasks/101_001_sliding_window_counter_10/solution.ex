  # Schedule the next cleanup message; :infinity disables periodic cleanup.
  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    Process.send_after(self(), :cleanup, interval_ms)
    :ok
  end