  defp row_map(headers, cells) do
    headers
    |> Enum.with_index()
    |> Enum.map(fn {header, i} -> {header, Enum.at(cells, i, "")} end)
    |> Map.new()
  end