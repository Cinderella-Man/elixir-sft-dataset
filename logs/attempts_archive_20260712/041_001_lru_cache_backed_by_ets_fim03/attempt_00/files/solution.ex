  def get(name, key) do
    data_table = data_table_name(name)

    # Read directly from ETS – no GenServer round-trip for the lookup itself.
    case :ets.lookup(data_table, key) do
      [{^key, {value, _ts}}] ->
        # Serialise the ordering update through the server.
        GenServer.call(name, {:touch, key})
        {:ok, value}

      [] ->
        :miss
    end
  end