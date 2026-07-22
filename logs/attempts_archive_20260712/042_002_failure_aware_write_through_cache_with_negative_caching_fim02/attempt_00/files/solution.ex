  def fetch(server, table, key, fallback_fn)
      when is_atom(table) and is_function(fallback_fn, 0) do
    pid = resolve_pid!(server)

    case :persistent_term.get({__MODULE__, pid, table}, :no_table) do
      :no_table ->
        GenServer.call(server, {:fetch, table, key, fallback_fn})

      tid ->
        case :ets.lookup(tid, key) do
          # Fast path: a cached success can be served without the GenServer.
          [{^key, {:ok, value}}] -> {:ok, value}
          # Misses and negative entries need serialised handling.
          _ -> GenServer.call(server, {:fetch, table, key, fallback_fn})
        end
    end
  end