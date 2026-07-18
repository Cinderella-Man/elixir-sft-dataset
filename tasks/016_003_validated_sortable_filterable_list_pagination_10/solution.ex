  # Only integers and integer-formatted strings are accepted; every other shape
  # (maps, lists, floats, booleans, partial numbers) is a bad request.
  defp parse_integer(value) when is_integer(value), do: {:ok, value}

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> {:ok, n}
      _ -> {:error, :invalid_filter}
    end
  end

  defp parse_integer(_value), do: {:error, :invalid_filter}