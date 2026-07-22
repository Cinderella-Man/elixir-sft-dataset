  def get(name, key) do
    case :ets.lookup(data_table_name(name), key) do
      [{^key, {value, _weight, _ts}}] ->
        GenServer.call(name, {:touch, key})
        {:ok, value}

      [] ->
        :miss
    end
  end