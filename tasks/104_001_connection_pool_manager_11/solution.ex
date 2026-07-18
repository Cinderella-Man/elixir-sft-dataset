  # Record `conn` as in use by `pid`, monitoring the owner.
  defp assign(conn, pid, state) do
    mon = Process.monitor(pid)
    %{state | in_use: Map.put(state.in_use, conn, {pid, mon})}
  end