@impl true
def handle_info({:fire, key}, state) do
  case Map.pop(state, key) do
    {nil, new_state} ->
      {:noreply, new_state}

    {entry, new_state} ->
      cond do
        entry.edge == :trailing -> run(entry.last_func)
        entry.edge == :both and entry.calls > 1 -> run(entry.last_func)
        true -> :ok
      end

      {:noreply, new_state}
  end
end