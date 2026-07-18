  @spec normalize_code(String.t() | integer()) :: String.t()
  defp normalize_code(code) when is_integer(code) do
    code
    |> Integer.to_string()
    |> String.pad_leading(@digits, "0")
  end

  defp normalize_code(code) when is_binary(code), do: code