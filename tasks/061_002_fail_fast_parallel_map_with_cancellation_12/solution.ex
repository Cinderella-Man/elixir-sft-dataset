  defp order_results(results) do
    results |> Map.keys() |> Enum.sort() |> Enum.map(&Map.fetch!(results, &1))
  end