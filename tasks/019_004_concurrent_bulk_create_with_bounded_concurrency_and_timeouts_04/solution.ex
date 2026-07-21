  # Tracking must survive `on_timeout: :kill_task`: a brutally killed task
  # never reaches its `after track_end()`, so a plain counter leaks upward and
  # the reported peak could exceed `max_concurrency`. Tracking LIVE pids and
  # pruning dead ones before each count keeps the high-water mark honest.
  @spec track_start() :: :ok
  defp track_start do
    caller = self()

    Agent.update(__MODULE__, fn st ->
      pids =
        st.running_pids
        |> Enum.filter(&Process.alive?/1)
        |> MapSet.new()
        |> MapSet.put(caller)

      %{st | running_pids: pids, peak: max(st.peak, MapSet.size(pids))}
    end)
  end
