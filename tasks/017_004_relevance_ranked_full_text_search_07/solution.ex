  defp tokenize(nil), do: []

  defp tokenize(str) when is_binary(str) do
    str
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
  end

  defp tokenize(_), do: []