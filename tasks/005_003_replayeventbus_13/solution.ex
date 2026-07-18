  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(ms) when is_integer(ms) and ms > 0 do
    Process.send_after(self(), :cleanup, ms)
  end