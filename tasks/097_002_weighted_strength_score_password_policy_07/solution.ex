  defp min_length_reason(password, %{min_length: min}) do
    if String.length(password) < min, do: :too_short, else: nil
  end