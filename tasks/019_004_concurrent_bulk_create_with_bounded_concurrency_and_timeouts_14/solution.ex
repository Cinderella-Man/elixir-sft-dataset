  @spec track_end() :: :ok
  defp track_end do
    Agent.update(__MODULE__, fn st -> %{st | running: st.running - 1} end)
  end