  defp maybe_expire_open(%{state: :open} = state) do
    if state.clock.() - state.opened_at >= state.config.reset_timeout_ms do
      %{state | state: :half_open, probes_in_flight: 0}
    else
      state
    end
  end

  defp maybe_expire_open(state), do: state