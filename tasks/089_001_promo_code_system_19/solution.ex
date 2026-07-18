  defp user_uses(state, code_string, user_id) do
    Map.get(state.user_uses, {code_string, user_id}, 0)
  end