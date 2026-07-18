  # Parse a value: either a quoted string or an unquoted token.
  defp parse_value("\"" <> rest) do
    parse_quoted_value(rest, "")
  end

  defp parse_value("") do
    # key= with empty value
    {:ok, "", ""}
  end

  defp parse_value(input) do
    # Unquoted value: everything until the next space.
    case String.split(input, ~r/\s/, parts: 2) do
      [value] -> {:ok, value, ""}
      [value, remaining] -> {:ok, value, remaining}
    end
  end