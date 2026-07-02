  @spec profile([row()], non_neg_integer()) :: profile()
  defp profile(rows, index) do
    cells = column_cells(rows, index)
    missing = length(rows) - length(cells)

    cell_cats = Enum.map(cells, fn cell -> {cell, categorize(cell)} end)

    nullable? = missing > 0 or Enum.any?(cell_cats, fn {_c, cat} -> cat == :null end)

    non_null = Enum.reject(cell_cats, fn {_c, cat} -> cat == :null end)
    values = Enum.map(non_null, fn {{value, _quoted?}, _cat} -> value end)
    categories = non_null |> Enum.map(fn {_c, cat} -> cat end) |> Enum.uniq()

    %{
      type: resolve(categories),
      nullable: nullable?,
      unique: length(values) == length(Enum.uniq(values))
    }
  end