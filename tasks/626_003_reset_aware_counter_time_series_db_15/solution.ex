  @spec series_points(map()) :: [point()]
  defp series_points(entry) do
    entry.chunks
    |> Map.values()
    |> Enum.concat()
    |> Enum.sort_by(fn {ts, _v} -> ts end)
  end