@impl GenServer
def handle_call({:fetch, table, key, fallback_fn}, _from, state) do
  {tid, state} = ensure_table(table, state)

  reply =
    case :ets.lookup(tid, key) do
      [{^key, {:ok, value}}] ->
        {:ok, value}

      [{^key, {:neg, reason, remaining}}] ->
        if remaining <= 1 do
          :ets.delete(tid, key)
        else
          :ets.insert(tid, {key, {:neg, reason, remaining - 1}})
        end

        {:error, reason}

      [] ->
        case fallback_fn.() do
          {:ok, value} ->
            :ets.insert(tid, {key, {:ok, value}})
            {:ok, value}

          {:error, reason} ->
            if state.negative_hits > 0 do
              :ets.insert(tid, {key, {:neg, reason, state.negative_hits}})
            end

            {:error, reason}

          other ->
            raise ArgumentError,
                  "fallback_fn must return {:ok, value} or {:error, reason}, " <>
                    "got: #{inspect(other)}"
        end
    end

  {:reply, reply, state}
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