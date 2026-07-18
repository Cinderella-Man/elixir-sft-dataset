  defp schedule_check(name, interval_ms) do
    Process.send_after(self(), {:check, name}, interval_ms)
  end