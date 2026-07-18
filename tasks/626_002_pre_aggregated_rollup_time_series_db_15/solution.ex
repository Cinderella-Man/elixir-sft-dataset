  @spec schedule_cleanup(non_neg_integer() | :infinity) :: :ok
  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end