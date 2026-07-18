  # Parse inside a quoted value, handling escaped quotes.
  # Unterminated quote
  defp parse_quoted_value("", _acc), do: :error

  defp parse_quoted_value("\\\"" <> rest, acc) do
    parse_quoted_value(rest, acc <> "\"")
  end

  defp parse_quoted_value("\"" <> rest, acc) do
    {:ok, acc, rest}
  end

  defp parse_quoted_value(<<ch::utf8, rest::binary>>, acc) do
    parse_quoted_value(rest, acc <> <<ch::utf8>>)
  end