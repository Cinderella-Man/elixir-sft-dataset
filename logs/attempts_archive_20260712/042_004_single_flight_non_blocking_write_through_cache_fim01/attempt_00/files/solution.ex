  # Single-flight participation. Runs the fallback in THIS process when elected
  # leader; blocks (via a parked GenServer call) when a follower.
  defp join_and_compute(server, table, key, fallback_fn) do
    case GenServer.call(server, {:join, table, key}, :infinity) do
      {:hit, value} ->
        {:ok, value}

      {:value, value} ->
        # A follower whose leader completed.
        {:ok, value}

      :retry ->
        # Leader failed; try again (we may become the new leader).
        join_and_compute(server, table, key, fallback_fn)

      {:leader, _ref} ->
        try do
          value = fallback_fn.()
          :ok = GenServer.call(server, {:done, table, key, value}, :infinity)
          {:ok, value}
        rescue
          e ->
            GenServer.call(server, {:fail, table, key}, :infinity)
            reraise e, __STACKTRACE__
        end
    end
  end