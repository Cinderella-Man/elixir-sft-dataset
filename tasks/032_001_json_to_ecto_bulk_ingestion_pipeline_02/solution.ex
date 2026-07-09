  @spec classify_rows(list() | nil, non_neg_integer(), boolean()) ::
          {non_neg_integer(), non_neg_integer()}
  defp classify_rows(_rows, count, false), do: {count, 0}
  defp classify_rows(nil, count, _ret), do: {count, 0}

  defp classify_rows(rows, _count, true) do
    Enum.reduce(rows, {0, 0}, fn row, {ins, upd} ->
      if timestamps_equal?(get_ts(row, :inserted_at), get_ts(row, :updated_at)) do
        {ins + 1, upd}
      else
        {ins, upd + 1}
      end
    end)
  end