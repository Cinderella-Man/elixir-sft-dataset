  defp t_rebalance(node) do
    bf = t_bf(node)

    cond do
      bf > 1 ->
        node =
          if t_bf(node.left) < 0 do
            t_node(node.s, node.f, node.id, t_rotate_left(node.left), node.right)
          else
            node
          end

        t_rotate_right(node)

      bf < -1 ->
        node =
          if t_bf(node.right) > 0 do
            t_node(node.s, node.f, node.id, node.left, t_rotate_right(node.right))
          else
            node
          end

        t_rotate_left(node)

      true ->
        node
    end
  end