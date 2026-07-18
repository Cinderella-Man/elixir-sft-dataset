  defp common_reason(password, %{common_passwords: list}) do
    lower = String.downcase(password)
    if Enum.any?(list, fn p -> String.downcase(p) == lower end), do: :common_password, else: nil
  end