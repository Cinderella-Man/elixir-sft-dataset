  defp parse_int_filter(params, key) do
    case Map.get(params, key) do
      nil -> {:ok, nil}
      raw -> parse_integer(raw)
    end
  end