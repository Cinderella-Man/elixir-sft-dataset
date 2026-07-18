  defp parse_media_range(range, default) do
    [type | params] = range |> String.split(";") |> Enum.map(&String.trim/1)
    {version_for(type, default), parse_q(params)}
  end