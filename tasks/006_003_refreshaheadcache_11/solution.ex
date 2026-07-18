  defp schedule_sweep(:infinity), do: :ok

  defp schedule_sweep(ms) when is_integer(ms) and ms > 0 do
    Process.send_after(self(), :sweep, ms)
  end