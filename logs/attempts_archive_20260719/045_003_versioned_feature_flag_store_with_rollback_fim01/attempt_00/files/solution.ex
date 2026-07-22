  defp write_version(state, flag, new_state) do
    v =
      case :ets.lookup(state.state_table, flag) do
        [{^flag, _s, cur_v}] -> cur_v
        [] -> 0
      end

    new_v = v + 1
    :ets.insert(state.state_table, {flag, new_state, new_v})
    :ets.insert(state.hist_table, {{flag, new_v}, new_state})
    new_v
  end