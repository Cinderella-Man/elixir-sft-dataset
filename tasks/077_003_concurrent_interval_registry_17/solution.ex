  defp t_max_child(acc, nil), do: acc
  defp t_max_child(acc, %{max_finish: mf}), do: max(acc, mf)