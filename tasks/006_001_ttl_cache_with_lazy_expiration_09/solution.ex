  defp schedule_sweep(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :sweep, interval_ms)
  end

  defp schedule_sweep(_), do: :ok