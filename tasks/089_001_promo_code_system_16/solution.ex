  # Per-user limits only apply when a user_id is provided.
  defp check_max_uses_per_user(%{max_uses_per_user: nil}, _code_string, _user_id, _state), do: :ok
  defp check_max_uses_per_user(_code, _code_string, nil, _state), do: :ok

  defp check_max_uses_per_user(%{max_uses_per_user: max}, code_string, user_id, state) do
    if user_uses(state, code_string, user_id) >= max do
      {:error, :max_uses_per_user_exceeded}
    else
      :ok
    end
  end