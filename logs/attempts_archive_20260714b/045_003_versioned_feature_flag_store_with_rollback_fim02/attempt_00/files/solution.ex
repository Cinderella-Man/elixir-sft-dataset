@impl true
def handle_call({:write, flag, new_state}, _from, state) do
  write_version(state, flag, new_state)
  {:reply, :ok, state}
end

def handle_call({:rollback, flag}, _from, state) do
  reply =
    case :ets.lookup(state.state_table, flag) do
      [] ->
        {:error, :unknown_flag}

      [{^flag, _cur, v}] when v < 2 ->
        {:error, :no_previous_version}

      [{^flag, _cur, v}] ->
        [{{^flag, _pv}, prev_state}] = :ets.lookup(state.hist_table, {flag, v - 1})
        write_version(state, flag, prev_state)
        :ok
    end

  {:reply, reply, state}
end