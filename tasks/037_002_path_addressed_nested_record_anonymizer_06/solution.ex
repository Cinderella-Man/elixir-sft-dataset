  defp parse_path(path) do
    path
    |> String.split(".")
    |> Enum.flat_map(&parse_segment/1)
  end