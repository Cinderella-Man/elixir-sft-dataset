  defp decrement_dependents(ids, in_degree, dependents) do
    Enum.reduce(ids, in_degree, fn id, acc ->
      dependents
      |> Map.get(id, [])
      |> Enum.reduce(acc, fn dependent, acc2 ->
        case Map.fetch(acc2, dependent) do
          {:ok, n} -> Map.put(acc2, dependent, n - 1)
          :error -> acc2
        end
      end)
    end)
  end