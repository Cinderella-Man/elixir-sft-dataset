  # Parse the raw CSV text into {headers, rows}.
  # Returns {headers :: [String.t()], rows :: [[String.t()]]}.
  defp parse_csv(text) do
    # NimbleCSV.parse_string/2 raises on completely empty input, so guard.
    lines =
      text
      |> String.trim_trailing()
      |> String.split(~r/\r?\n/, parts: 2)

    case lines do
      [""] ->
        # Only whitespace / effectively empty — but import_string won't
        # receive truly empty strings from import_file (caught earlier).
        {[], []}

      [header_line] ->
        # Header only, no data rows.
        headers = parse_header(header_line)
        {headers, []}

      [_header_line | _rest] ->
        # At least one data row. Use NimbleCSV for proper RFC 4180 parsing.
        [headers | rows] = CsvImporter.Parser.parse_string(text, skip_headers: false)
        trimmed_headers = Enum.map(headers, &String.trim/1)
        {trimmed_headers, rows}
    end
  end