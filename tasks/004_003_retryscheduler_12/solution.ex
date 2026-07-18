  defp schedule_tick(:infinity), do: :ok

  defp schedule_tick(ms) when is_integer(ms) and ms > 0 do
    Process.send_after(self(), :tick, ms)
  end