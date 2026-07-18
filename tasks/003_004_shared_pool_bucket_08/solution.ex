  defp refill_global(state, now) do
    elapsed = now - state.global_last_update_at
    added = elapsed * state.global_refill_rate / 1000
    new_free = min(state.global_capacity * 1.0, state.global_free + added)
    %{state | global_free: new_free, global_last_update_at: now}
  end