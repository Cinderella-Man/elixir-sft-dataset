  defp check_special(_password, %{require_special: false}), do: :ok

  defp check_special(password, _cfg) do
    if String.match?(password, ~r/[^a-zA-Z0-9]/), do: :ok, else: {:violation, :no_special}
  end