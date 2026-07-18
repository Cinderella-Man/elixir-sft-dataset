  defp existing_prereqs(table, flag) do
    case :ets.lookup(table, flag) do
      [{^flag, _s, ps}] -> ps
      [] -> []
    end
  end