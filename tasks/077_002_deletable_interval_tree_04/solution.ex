  defp delete_here(nil, right), do: right
  defp delete_here(left, nil), do: left

  defp delete_here(left, right) do
    successor = min_interval(right)
    {nr, _found} = do_delete(right, successor)
    balance(successor, left, nr)
  end