  @impl true
  def handle_call({:touch, key}, _from, state) do
    case :ets.lookup(state.data_table, key) do
      [{^key, {value, freq, seq}}] ->
        {new_seq, state} = next_counter(state)
        :ets.delete(state.order_table, {freq, seq})
        :ets.insert(state.order_table, {{freq + 1, new_seq}, key})
        :ets.insert(state.data_table, {key, {value, freq + 1, new_seq}})
        {:reply, :ok, state}

      [] ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:put, key, value}, _from, state) do
    state =
      case :ets.lookup(state.data_table, key) do
        [{^key, {_old_value, freq, seq}}] ->
          {new_seq, state} = next_counter(state)
          :ets.delete(state.order_table, {freq, seq})
          :ets.insert(state.order_table, {{freq + 1, new_seq}, key})
          :ets.insert(state.data_table, {key, {value, freq + 1, new_seq}})
          state

        [] ->
          state = maybe_evict(state)
          {new_seq, state} = next_counter(state)
          :ets.insert(state.order_table, {{1, new_seq}, key})
          :ets.insert(state.data_table, {key, {value, 1, new_seq}})
          state
      end

    {:reply, :ok, state}
  end