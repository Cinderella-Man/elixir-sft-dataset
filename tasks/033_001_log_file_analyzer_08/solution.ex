  defp process_line(raw_line, acc) do
    # Silently skip blank lines.
    trimmed = String.trim(raw_line)

    if trimmed == "" do
      acc
    else
      case parse_line(trimmed) do
        {:ok, entry} ->
          accumulate(acc, entry)

        :error ->
          %{acc | malformed: acc.malformed + 1}
      end
    end
  end