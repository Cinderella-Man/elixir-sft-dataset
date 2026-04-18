defp handle_open(func, state) do
  now = state.clock.()
  elapsed = now - state.opened_at

  if elapsed >= state.reset_timeout_ms do
    half_open_state = %{state | circuit_state: :half_open, probe_count: 0}
    handle_half_open(func, half_open_state)
  else
    {:reply, {:error, :circuit_open}, state}
  end
end
