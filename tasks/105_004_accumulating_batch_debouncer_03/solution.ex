@impl true
def handle_info({:flush, key}, state) do
  case Map.pop(state, key) do
    {%{items: items, handler: handler}, new_state} ->
      batch = Enum.reverse(items)
      spawn(fn -> handler.(batch) end)
      {:noreply, new_state}

    {nil, new_state} ->
      {:noreply, new_state}
  end
end