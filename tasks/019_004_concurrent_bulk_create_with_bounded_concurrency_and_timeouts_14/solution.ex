  @spec track_end() :: :ok
  defp track_end do
    caller = self()

    Agent.update(__MODULE__, fn st ->
      %{st | running_pids: MapSet.delete(st.running_pids, caller)}
    end)
  end
