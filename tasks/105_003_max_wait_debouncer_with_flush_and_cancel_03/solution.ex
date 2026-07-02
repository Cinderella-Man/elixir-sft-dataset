@impl true
def handle_info({:fire, key}, state) do
  case Map.pop(state, key) do
    {%{func: func}, new_state} ->
      run(func)
      {:noreply, new_state}

    {nil, new_state} ->
      {:noreply, new_state}
  end
end