  def delete(server, table, key, deleter_fn)
      when is_atom(table) and is_function(deleter_fn, 0) do
    GenServer.call(server, {:delete, table, key, deleter_fn})
  end