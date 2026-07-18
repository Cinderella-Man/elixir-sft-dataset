  @spec base32?(String.t()) :: boolean()
  defp base32?(string) do
    string
    |> String.to_charlist()
    |> Enum.all?(&(&1 in @base32_alphabet))
  end