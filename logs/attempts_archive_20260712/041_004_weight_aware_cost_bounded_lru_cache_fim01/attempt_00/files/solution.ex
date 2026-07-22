  # Evict LRU entries one at a time until `incoming` fits within the budget.
  defp evict_until_fits(state, incoming) do
    if state.total_weight + incoming > state.max_weight and
         :ets.info(state.data_table, :size) > 0 do
      lru_ts = :ets.first(state.order_table)
      [{^lru_ts, victim}] = :ets.lookup(state.order_table, lru_ts)
      [{^victim, {_v, victim_w, ^lru_ts}}] = :ets.lookup(state.data_table, victim)
      :ets.delete(state.order_table, lru_ts)
      :ets.delete(state.data_table, victim)
      evict_until_fits(%{state | total_weight: state.total_weight - victim_w}, incoming)
    else
      state
    end
  end