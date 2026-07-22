  defp delete_here(%{left: nil, right: r}), do: r
  defp delete_here(%{left: l, right: nil}), do: l

  defp delete_here(%{left: l, right: r}) do
    successor = min_interval(r)
    {nr, _found} = do_delete(r, successor)
    rebalance(make_node(successor, l, nr))
  end