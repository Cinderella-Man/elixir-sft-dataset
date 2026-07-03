defp maybe_start_next(key, key_state) do
  case key_state.queue do
    [{from, func} | rest] ->
      new_key_state = %{key_state | queue: rest}
      start_task(key, func, from, new_key_state)

    [] ->
      key_state
  end
end