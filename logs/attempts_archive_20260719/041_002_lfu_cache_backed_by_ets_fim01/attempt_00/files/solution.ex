  defp maybe_evict(state) do
    if :ets.info(state.data_table, :size) >= state.max_size do
      # Smallest composite key = lowest frequency, LRU tie-break.
      victim_composite = :ets.first(state.order_table)
      [{^victim_composite, victim_key}] = :ets.lookup(state.order_table, victim_composite)
      :ets.delete(state.order_table, victim_composite)
      :ets.delete(state.data_table, victim_key)
    end

    state
  end