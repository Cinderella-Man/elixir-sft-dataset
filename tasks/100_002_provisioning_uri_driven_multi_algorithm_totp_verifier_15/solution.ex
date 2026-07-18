  @spec parse_digits(map()) :: {:ok, 6 | 7 | 8} | {:error, :invalid_digits}
  defp parse_digits(params) do
    case Map.get(params, "digits", "6") do
      "6" -> {:ok, 6}
      "7" -> {:ok, 7}
      "8" -> {:ok, 8}
      _other -> {:error, :invalid_digits}
    end
  end