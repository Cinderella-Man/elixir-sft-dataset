  defp default_atom(header) do
    header
    |> String.downcase()
    |> String.replace(~r/\s+/, "_")
    |> String.to_atom()
  end