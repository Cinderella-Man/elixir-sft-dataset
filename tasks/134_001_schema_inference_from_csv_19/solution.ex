  @spec parse_csv(String.t()) :: [row()]
  defp parse_csv(content) do
    case strip_one_newline(content) do
      "" -> []
      stripped -> parse_chars(stripped, "", false, false, [], [])
    end
  end