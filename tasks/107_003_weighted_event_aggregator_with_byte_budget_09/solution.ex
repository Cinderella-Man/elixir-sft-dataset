  # Start the interval timer only on the transition from empty to non-empty.
  defp ensure_timer(%{timer: nil} = state), do: start_timer(state)
  defp ensure_timer(state), do: state