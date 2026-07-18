  defp all_ids(state) do
    state.documents |> Map.keys() |> MapSet.new()
  end