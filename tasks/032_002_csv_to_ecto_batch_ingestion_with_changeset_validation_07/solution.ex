  @spec parse_csv(String.t()) :: {:ok, {[String.t()], [[String.t()]]}}
  defp parse_csv(path) do
    raw = File.read!(path)

    # NimbleCSV.parse_string with skip_headers: false returns every row as a
    # list of fields; the first row is split off as the header list.
    parsed =
      raw
      |> CsvIngestion.Parser.parse_string(skip_headers: false)
      |> then(fn
        [] -> {[], []}
        [hdr | rows] -> {hdr, rows}
      end)

    case parsed do
      {_headers, _data} = pair -> {:ok, pair}
    end
  end