  defp parse_price(nil), do: :error
  defp parse_price(v) when is_integer(v), do: {:ok, v}

  defp parse_price(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp parse_price(_), do: :error