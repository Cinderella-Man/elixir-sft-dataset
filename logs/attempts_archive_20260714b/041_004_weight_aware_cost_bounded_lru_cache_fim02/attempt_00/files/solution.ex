  # Remove an existing entry for `key` (if any) and reclaim its weight.
  defp release_existing(state, key) do
    case :ets.lookup(state.data_table, key) do
      [{^key, {_old_value, old_w, old_ts}}] ->
        :ets.delete(state.order_table, old_ts)
        :ets.delete(state.data_table, key)
        %{state | total_weight: state.total_weight - old_w}

      [] ->
        state
    end
  end