  # Fallback header parser for the single-line case (no data rows).
  defp parse_header(line) do
    [row] = CsvImporter.Parser.parse_string(line <> "\n", skip_headers: false)
    Enum.map(row, &String.trim/1)
  end