  @spec track_start() :: :ok
  defp track_start do
    Agent.update(__MODULE__, fn st ->
      running = st.running + 1
      %{st | running: running, peak: max(st.peak, running)}
    end)
  end