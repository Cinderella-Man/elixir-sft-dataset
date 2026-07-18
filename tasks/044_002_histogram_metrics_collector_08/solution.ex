  defp counter(key) do
    case :ets.lookup(@table, key) do
      [{^key, v}] -> v
      [] -> 0
    end
  end