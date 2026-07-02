  # A completed use: bump the count, then retire-or-return the connection.
  defp release(conn, state) do
    count = Map.get(state.uses, conn, 0) + 1
    state = %{state | uses: Map.delete(state.uses, conn)}

    if retire?(count, state.max_uses) do
      state.destroy.(conn)
      state = %{state | total: state.total - 1}

      case :queue.out(state.waiters) do
        {{:value, waiter}, rest} ->
          _ = Process.cancel_timer(waiter.timer)
          new = state.create.()
          in_use = Map.put(state.in_use, new, {waiter.pid, waiter.mon})
          GenServer.reply(waiter.from, {:ok, new})

          %{
            state
            | waiters: rest,
              in_use: in_use,
              total: state.total + 1,
              uses: Map.put(state.uses, new, 0)
          }

        {:empty, _} ->
          state
      end
    else
      case :queue.out(state.waiters) do
        {{:value, waiter}, rest} ->
          _ = Process.cancel_timer(waiter.timer)
          in_use = Map.put(state.in_use, conn, {waiter.pid, waiter.mon})
          GenServer.reply(waiter.from, {:ok, conn})
          %{state | waiters: rest, in_use: in_use, uses: Map.put(state.uses, conn, count)}

        {:empty, _} ->
          %{state | available: [conn | state.available], uses: Map.put(state.uses, conn, count)}
      end
    end
  end