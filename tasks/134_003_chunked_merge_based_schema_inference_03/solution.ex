  @spec build_categories([row()]) :: %{optional(non_neg_integer()) => MapSet.t(category())}
  defp build_categories(rows) do
    Enum.reduce(rows, %{}, fn row, acc ->
      row
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {cell, index}, inner ->
        case categorize(cell) do
          :null -> inner
          category -> Map.update(inner, index, MapSet.new([category]), &MapSet.put(&1, category))
        end
      end)
    end)
  end