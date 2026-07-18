  @spec map_headers([String.t()], map() | nil) :: [atom()]
  defp map_headers(headers, nil) do
    Enum.map(headers, fn h ->
      h
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/\s+/, "_")
      |> String.to_atom()
    end)
  end

  defp map_headers(headers, mapping) when is_map(mapping) do
    Enum.map(headers, fn h ->
      trimmed = String.trim(h)
      Map.get(mapping, trimmed, default_atom(trimmed))
    end)
  end