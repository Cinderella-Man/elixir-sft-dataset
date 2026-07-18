  defp disarm(entry) do
    _ = Process.cancel_timer(entry.warn_timer)
    _ = Process.cancel_timer(entry.timeout_timer)
    entry
  end