def all do
  :ets.tab2list(@table)
  |> Map.new()
end