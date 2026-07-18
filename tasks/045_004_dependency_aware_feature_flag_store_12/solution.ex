  defp record(flag) do
    case :ets.lookup(table(), flag) do
      [{^flag, state, prereqs}] -> {state, prereqs}
      [] -> nil
    end
  end