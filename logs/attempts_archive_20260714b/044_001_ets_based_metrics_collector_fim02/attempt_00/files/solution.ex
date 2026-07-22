def get(name) do
  case :ets.lookup(@table, name) do
    [{^name, value}] -> value
    [] -> nil
  end
end