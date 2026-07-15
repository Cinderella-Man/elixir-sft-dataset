@impl true
def handle_info({:fire, key, token}, state) do
  case Map.get(state, key) do
    # Only the CURRENT burst's token may fire; a stale timer message from a
    # superseded burst (its cancel arrived too late) is discarded.
    %{token: ^token} = entry ->
      cond do
        entry.edge == :trailing -> run(entry.last_func)
        entry.edge == :both and entry.calls > 1 -> run(entry.last_func)
        true -> :ok
      end

      {:noreply, Map.delete(state, key)}

    _ ->
      {:noreply, state}
  end
end