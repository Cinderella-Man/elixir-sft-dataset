  defp deliver(conn, state) do
    case :queue.out(state.waiters) do
      {{:value, waiter}, rest} ->
        state = %{state | waiters: rest}
        _ = Process.cancel_timer(waiter.timer)

        if state.validate.(conn) do
          in_use = Map.put(state.in_use, conn, {waiter.pid, waiter.mon})
          GenServer.reply(waiter.from, {:ok, conn})
          %{state | in_use: in_use}
        else
          state.destroy.(conn)
          new_conn = state.create.()
          in_use = Map.put(state.in_use, new_conn, {waiter.pid, waiter.mon})
          GenServer.reply(waiter.from, {:ok, new_conn})
          # total unchanged: one destroyed, one created.
          %{state | in_use: in_use}
        end

      {:empty, _} ->
        %{state | available: [conn | state.available]}
    end
  end