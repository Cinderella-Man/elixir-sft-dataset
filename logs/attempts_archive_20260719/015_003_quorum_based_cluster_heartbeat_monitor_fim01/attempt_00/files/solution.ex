  @spec run_poll(map(), term()) :: map()
  defp run_poll(cluster, name) do
    healthy = Enum.count(cluster.check_funcs, fn check -> check.() == :ok end)
    new_status = if healthy >= cluster.quorum, do: :up, else: :down

    if cluster.status == :up and new_status == :down do
      cluster.notify.(name, healthy)
    end

    %{cluster | status: new_status, healthy: healthy}
  end