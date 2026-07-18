  # Pull the first valid connection off the available list, discarding
  # (and destroying) any invalid ones encountered along the way.
  defp take_valid(state), do: do_take(state.available, state)