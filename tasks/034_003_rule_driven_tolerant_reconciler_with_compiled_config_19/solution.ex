  defp normalize_string(value) do
    value |> String.trim() |> String.downcase()
  end