  defp do_cleanup(state) do
    cutoff = state.clock.() - state.retention_ms

    state.shards
    |> Tuple.to_list()
    |> Enum.each(fn pid -> GenServer.call(pid, {:cleanup, cutoff}) end)

    :ok
  end