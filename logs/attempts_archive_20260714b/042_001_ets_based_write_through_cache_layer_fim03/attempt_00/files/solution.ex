@impl GenServer
# Fetch — serialised write path (also handles first-time table creation).
def handle_call({:fetch, table, key, fallback_fn}, _from, state) do
  {tid, state} = ensure_table(table, state)

  # Re-check ETS before invoking the fallback: a concurrent caller that also
  # missed the cache and ended up here first may have already populated it.
  value =
    case :ets.lookup(tid, key) do
      [{^key, cached}] ->
        cached

      [] ->
        fresh = fallback_fn.()
        :ets.insert(tid, {key, fresh})
        fresh
    end

  {:reply, {:ok, value}, state}
end

def handle_call({:invalidate, table, key}, _from, state) do
  case Map.get(state.tables, table) do
    nil -> :ok
    tid -> :ets.delete(tid, key)
  end

  {:reply, :ok, state}
end

def handle_call({:invalidate_all, table}, _from, state) do
  case Map.get(state.tables, table) do
    nil -> :ok
    tid -> :ets.delete_all_objects(tid)
  end

  {:reply, :ok, state}
end