  defp ensure_table(table, %{tables: tables} = state) do
    case Map.get(tables, table) do
      nil ->
        # Named tables would collide if multiple CacheLayer instances use the
        # same atom, so we use unnamed tables and track tids ourselves.
        tid = :ets.new(table, [:set, :public])

        # Publish so fetch/4 can bypass the GenServer on future cache hits.
        :persistent_term.put({__MODULE__, self(), table}, tid)

        new_state = %{state | tables: Map.put(tables, table, tid)}
        {tid, new_state}

      tid ->
        {tid, state}
    end
  end