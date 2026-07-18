  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval) when is_integer(interval) do
    Process.send_after(self(), :cleanup, interval)
  end