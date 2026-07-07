  defp record_use(state, code_string, user_id) do
    state = update_in(state.total_uses[code_string], &((&1 || 0) + 1))

    case user_id do
      nil -> state
      _ -> update_in(state.user_uses[{code_string, user_id}], &((&1 || 0) + 1))
    end
  end