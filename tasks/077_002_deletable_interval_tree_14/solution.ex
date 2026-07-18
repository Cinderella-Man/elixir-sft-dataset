  defp max_with_child(acc, nil), do: acc
  defp max_with_child(acc, %{max_finish: mf}), do: max(acc, mf)