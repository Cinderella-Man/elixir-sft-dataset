# Evict the LRU entry when the cache is at max capacity.
@spec maybe_evict(state()) :: state()
defp maybe_evict(state) do
  current_size = :ets.info(state.data_table, :size)

  if current_size >= state.max_size do
    # `first/1` on an ordered_set returns the smallest key, i.e. the oldest
    # timestamp, which is exactly the least-recently used entry.
    lru_ts = :ets.first(state.order_table)
    [{^lru_ts, lru_key}] = :ets.lookup(state.order_table, lru_ts)
    :ets.delete(state.order_table, lru_ts)
    :ets.delete(state.data_table, lru_key)
  end

  state
end