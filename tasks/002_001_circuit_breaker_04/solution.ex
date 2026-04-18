defp handle_half_open(func, state) do
  if state.probe_count >= state.half_open_max_probes do
    {:reply, {:error, :circuit_open}, state}
  else
    new_state = %{state | probe_count: state.probe_count + 1}
    {result, success?} = execute(func)

    if success? do
      {:reply, result, reset_to_closed(new_state)}
    else
      {:reply, result, trip_open(new_state)}
    end
  end
end
