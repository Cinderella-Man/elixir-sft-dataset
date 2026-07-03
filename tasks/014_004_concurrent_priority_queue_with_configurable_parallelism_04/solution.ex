defp maybe_notify_drain(state) do
  if queue_empty?(state) and map_size(state.active_workers) == 0 do
    notify_drain_waiters(state)
  else
    state
  end
end