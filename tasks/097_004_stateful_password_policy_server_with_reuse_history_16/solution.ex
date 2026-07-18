  defp check_common(password, %{common_passwords: list}) do
    lower = String.downcase(password)

    if Enum.any?(list, fn p -> String.downcase(p) == lower end),
      do: {:violation, :common_password},
      else: :ok
  end