  # Convert a MapSet of key values to the corresponding list of records,
  # preserving insertion order by sorting keys for determinism.
  @spec map_set_to_records(MapSet.t(), %{term() => record_t()}) :: [record_t()]
  defp map_set_to_records(key_set, index) do
    key_set
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.map(&Map.fetch!(index, &1))
  end