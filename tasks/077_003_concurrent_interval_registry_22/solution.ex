  defp t_insert(nil, s, f, id), do: t_node(s, f, id, nil, nil)

  defp t_insert(node, s, f, id) do
    updated =
      if {s, f, id} < t_key(node) do
        t_node(node.s, node.f, node.id, t_insert(node.left, s, f, id), node.right)
      else
        t_node(node.s, node.f, node.id, node.left, t_insert(node.right, s, f, id))
      end

    t_rebalance(updated)
  end