defp handle_closed(func, state) do
  {result, success?} = execute(func)

  if success? do
    {:reply, result, %{state | failure_count: 0}}
  else
    new_count = state.failure_count + 1
    new_state = %{state | failure_count: new_count}

    if new_count >= state.failure_threshold do
      {:reply, result, trip_open(new_state)}
    else
      {:reply, result, new_state}
    end
  end
end
