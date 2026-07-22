@impl true
def handle_call({:touch, key}, _from, state) do
  case :ets.lookup(state.data_table, key) do
    [{^key, {value, old_ts}}] ->
      {new_ts, state} = next_counter(state)
      :ets.delete(state.order_table, old_ts)
      :ets.insert(state.order_table, {new_ts, key})
      :ets.insert(state.data_table, {key, {value, new_ts}})
      {:reply, :ok, state}

    [] ->
      {:reply, :ok, state}
  end
end

def handle_call({:put, key, value}, _from, state) do
  state =
    case :ets.lookup(state.data_table, key) do
      [{^key, {_old, old_ts}}] ->
        {new_ts, state} = next_counter(state)
        :ets.delete(state.order_table, old_ts)
        :ets.insert(state.order_table, {new_ts, key})
        :ets.insert(state.data_table, {key, {value, new_ts}})
        state

      [] ->
        state = maybe_evict(state)
        {new_ts, state} = next_counter(state)
        :ets.insert(state.order_table, {new_ts, key})
        :ets.insert(state.data_table, {key, {value, new_ts}})
        state
    end

  {:reply, :ok, state}
end