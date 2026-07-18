  defp to_records(key_set, index) do
    key_set
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.map(&Map.fetch!(index, &1))
  end