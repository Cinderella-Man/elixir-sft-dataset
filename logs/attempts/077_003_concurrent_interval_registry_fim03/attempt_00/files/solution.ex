  defp t_delete_here(%{left: nil, right: r}), do: r
  defp t_delete_here(%{left: l, right: nil}), do: l

  defp t_delete_here(%{left: l, right: r}) do
    succ = t_min(r)
    nr = t_delete(r, succ.s, succ.f, succ.id)
    t_rebalance(t_node(succ.s, succ.f, succ.id, l, nr))
  end