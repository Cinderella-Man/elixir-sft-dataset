  defp cleanup(mon, timer) do
    Process.demonitor(mon, [:flush])
    Process.cancel_timer(timer)
    :ok
  end