  defp check_lowercase(_password, %{require_lowercase: false}), do: :ok

  defp check_lowercase(password, _cfg) do
    if String.match?(password, ~r/[a-z]/), do: :ok, else: {:violation, :no_lowercase}
  end