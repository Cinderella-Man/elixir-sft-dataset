  def all do
    :ets.foldl(
      fn {{name, _second}, amount}, acc ->
        Map.update(acc, name, amount, &(&1 + amount))
      end,
      %{},
      @table
    )
  end