  defp parse_cursor(nil), do: 0

  defp parse_cursor(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _rest} when n >= 0 -> n
      _ -> 0
    end
  end