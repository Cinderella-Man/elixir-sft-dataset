def fetch(server, table, key, fallback_fn)
    when is_atom(table) and is_function(fallback_fn, 0) do
  pid = resolve_pid!(server)

  case :persistent_term.get({__MODULE__, pid, table}, :no_table) do
    :no_table ->
      # Table has not been created yet; let the GenServer handle everything,
      # including table creation.
      GenServer.call(server, {:fetch, table, key, fallback_fn})

    tid ->
      # Table exists — try a direct ETS read (no GenServer involved).
      case :ets.lookup(tid, key) do
        [{^key, value}] ->
          {:ok, value}

        [] ->
          # Cache miss: serialise through the GenServer so only one caller
          # runs the fallback.
          GenServer.call(server, {:fetch, table, key, fallback_fn})
      end
  end
end