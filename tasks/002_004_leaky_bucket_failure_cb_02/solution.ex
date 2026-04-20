# Lazily subtract the leak accumulated since the last update, clamped at 0,
# and advance `last_update_at` to now.
defp apply_leak(state) do
  now = state.clock.()
  elapsed_ms = now - state.last_update_at
  leak = elapsed_ms * state.config.leak_rate_per_sec / 1000
  new_level = max(0.0, state.bucket_level - leak)
  %{state | bucket_level: new_level, last_update_at: now}
end
