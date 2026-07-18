  @spec default_names([row()]) :: [String.t()]
  defp default_names(rows) do
    ncols =
      case Enum.map(rows, &length/1) do
        [] -> 0
        lengths -> Enum.max(lengths)
      end

    Enum.map(1..ncols//1, fn i -> "column_#{i}" end)
  end