defp reset_idle(state) do
  if state.idle_timer, do: Process.cancel_timer(state.idle_timer)
  timer = Process.send_after(self(), {:idle_flush, state.gen}, state.idle_ms)
  %{state | idle_timer: timer}
end