  @spec schedule_cleanup(:infinity | non_neg_integer()) :: :ok | reference()
  defp schedule_cleanup(:infinity), do: :ok
  defp schedule_cleanup(interval), do: Process.send_after(self(), :cleanup, interval)