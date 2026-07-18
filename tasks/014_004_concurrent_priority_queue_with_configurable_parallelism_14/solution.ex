  defp notify_drain_waiters(%{drain_waiters: []} = state), do: state

  defp notify_drain_waiters(state) do
    Enum.each(state.drain_waiters, &GenServer.reply(&1, :ok))
    %{state | drain_waiters: []}
  end