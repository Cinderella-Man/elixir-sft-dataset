  defp check_reuse(password, %{previous_passwords: list}) do
    if password in list, do: {:violation, :reused_password}, else: :ok
  end