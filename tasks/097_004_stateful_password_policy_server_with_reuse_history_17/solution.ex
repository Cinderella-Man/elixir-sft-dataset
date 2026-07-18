  defp check_reuse(password, %{history: history}) do
    if password in history, do: {:violation, :reused_password}, else: :ok
  end