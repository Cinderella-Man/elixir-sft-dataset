  defp compare_key(:asc, {v1, id1}, {v2, id2}) do
    cond do
      v1 < v2 -> :before
      v1 > v2 -> :after
      id1 < id2 -> :before
      id1 > id2 -> :after
      true -> :eq
    end
  end

  defp compare_key(:desc, {v1, id1}, {v2, id2}) do
    cond do
      v1 > v2 -> :before
      v1 < v2 -> :after
      id1 > id2 -> :before
      id1 < id2 -> :after
      true -> :eq
    end
  end