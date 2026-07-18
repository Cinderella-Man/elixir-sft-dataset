  defp current_state(flag) do
    case :ets.lookup(state_table(), flag) do
      [{^flag, state, _v}] -> state
      [] -> nil
    end
  end