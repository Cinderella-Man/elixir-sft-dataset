  defp character_classes(password) do
    [~r/[A-Z]/, ~r/[a-z]/, ~r/[0-9]/, ~r/[^a-zA-Z0-9]/]
    |> Enum.count(fn re -> String.match?(password, re) end)
  end