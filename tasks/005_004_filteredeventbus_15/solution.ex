  defp eval_clause({:eq, path, value}, event), do: fetch(event, path) == value
  defp eval_clause({:neq, path, value}, event), do: fetch(event, path) != value

  defp eval_clause({:gt, path, value}, event), do: num_cmp(fetch(event, path), value, &>/2)
  defp eval_clause({:lt, path, value}, event), do: num_cmp(fetch(event, path), value, &</2)
  defp eval_clause({:gte, path, value}, event), do: num_cmp(fetch(event, path), value, &>=/2)
  defp eval_clause({:lte, path, value}, event), do: num_cmp(fetch(event, path), value, &<=/2)

  defp eval_clause({:in, path, list}, event), do: fetch(event, path) in list

  defp eval_clause({:exists, path}, event), do: fetch(event, path) != nil

  defp eval_clause({:any, subs}, event), do: Enum.any?(subs, &eval_clause(&1, event))

  defp eval_clause({:none, subs}, event), do: not Enum.any?(subs, &eval_clause(&1, event))