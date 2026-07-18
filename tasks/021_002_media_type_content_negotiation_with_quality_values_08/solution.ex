  defp parse_accept(accept, default) do
    accept
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_media_range(&1, default))
    |> Enum.reject(fn {v, q} -> is_nil(v) or q <= 0 end)
  end