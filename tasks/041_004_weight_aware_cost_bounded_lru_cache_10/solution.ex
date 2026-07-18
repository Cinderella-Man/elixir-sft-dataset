  @impl true
  def handle_call(:weight, _from, state) do
    {:reply, state.total_weight, state}
  end

  def handle_call({:touch, key}, _from, state) do
    case :ets.lookup(state.data_table, key) do
      [{^key, {value, w, old_ts}}] ->
        {new_ts, state} = next_counter(state)
        :ets.delete(state.order_table, old_ts)
        :ets.insert(state.order_table, {new_ts, key})
        :ets.insert(state.data_table, {key, {value, w, new_ts}})
        {:reply, :ok, state}

      [] ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:put, key, value, weight}, _from, state) do
    cond do
      not (is_integer(weight) and weight > 0) ->
        {:reply, {:error, :invalid_weight}, state}

      weight > state.max_weight ->
        {:reply, {:error, :too_large}, state}

      true ->
        # Treat an update as remove-then-insert: release the old weight first.
        state = release_existing(state, key)
        state = evict_until_fits(state, weight)

        {new_ts, state} = next_counter(state)
        :ets.insert(state.order_table, {new_ts, key})
        :ets.insert(state.data_table, {key, {value, weight, new_ts}})
        state = %{state | total_weight: state.total_weight + weight}

        {:reply, :ok, state}
    end
  end