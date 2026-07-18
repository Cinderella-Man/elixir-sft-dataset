  defp t_delete(nil, _s, _f, _id), do: nil

  defp t_delete(node, s, f, id) do
    key = {s, f, id}
    nkey = t_key(node)

    cond do
      key < nkey ->
        t_rebalance(t_node(node.s, node.f, node.id, t_delete(node.left, s, f, id), node.right))

      key > nkey ->
        t_rebalance(t_node(node.s, node.f, node.id, node.left, t_delete(node.right, s, f, id)))

      true ->
        t_delete_here(node)
    end
  end