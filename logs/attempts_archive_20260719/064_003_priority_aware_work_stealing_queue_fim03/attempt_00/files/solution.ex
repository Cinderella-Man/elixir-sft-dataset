  # Merge two descending-sorted lists into one descending-sorted list.
  defp merge_desc(a, []), do: a
  defp merge_desc([], b), do: b

  defp merge_desc([{pa, _} = ha | ta] = left, [{pb, _} = hb | tb] = right) do
    if pa >= pb do
      [ha | merge_desc(ta, right)]
    else
      [hb | merge_desc(left, tb)]
    end
  end